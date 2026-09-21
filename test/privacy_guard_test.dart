// 守卫：仓库里不许再出现真实个人信息（2026-09-21 立 · 用户原话「关于4，加」）
//
// 背景：2026-09-21 做了一轮「仓库内真实数据脱敏 + 改写全部提交历史」（真实姓名 / 学号 / 学籍号 /
// 证件号 / 手机号 / 家庭住址 / 考生号 / 通知书号 / 校园网与邮箱口令 / CAS 票据 / 会话 / 平台令牌
// 全部换成合成值）。本文件是那次清洗的**回归绊线**：谁再把真实值粘回来，这里就红。
//
// 两类判据：
//   ① 结构类（形状 + 白名单）：身份证 / 手机号 / CAS 票据（TGT- · ST-）/ 会话（SESSION= · JSESSIONID=）/
//      平台令牌（openId= · cardinfo=）/ 学籍号（2016xxxxxxxx）/ 学号（2xxxxxxxxx）/ 通知书号 / MAC。
//      白名单里只放**合成值**与**公开的班级编号**。
//   ② 自由文本类（加盐 SHA-256 摘要黑名单）：真人姓名（2~4 字 CJK 词）与真实地址（8 字 CJK 窗口）。
//      姓名与地址没有可靠形状，只能对着名单查；摘要里不落明文。
//
// ⚠ 盐写在本文件里 ⇒ ② 是「绊线」不是「保密手段」：摘要可以被暴力枚举反推。
//    之所以仍这么做：这些值在改写前的公开历史里本来就存在过，绊线的价值是**防止再次写回来**，
//    而不是把已经公开过的东西再藏一遍。真要更严，就把 SALT 换成 CI secret，本文件改成读环境变量。
//
// 维护：新增真实值 → 跑 `python %TEMP%\gitgrp\gen_guard.py` 重新生成（脚本不入库）。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const String _salt = 'e7c1a9f43b5d2e8061fa0c9d47b3e215';

const Set<String> _nameDigests = <String>{
  '7cfa2ea8ba8103d8325f9b4095f2160dbf30d4222281de50a3bf0abb6a0a7697', '37d4cbd6d6c690e685dcbb03f168b5ad7a117a52b99f51b6f6c4f4fb7c655f86', 'c7a943351ab284222ce4ebe67127b22fde577224974a9a9682d29c27761ad519', '96b00c66b828c5bc1465135762cbb18d1091c59db188b4ac0fbe7a281b2e212d',
  'ca21d1778a3e869af219540acb242885fa0e900a7c241e3211799be901bb6b5c', '4c6fff002e90db1b9642f13fc060ab913761ba782ad7a89dae2d44a007e52e03', '954238da185ef287079870a2c05e06952b0d14618ec4114c1e9bf7be62da3407', 'aa4728f4a1635b9248473eb16bf23393e10f8847bae9c245a9c39935467ca30a',
  'a13a7fa53619bf288e3c909ef19512357b9a95ce122ed4fd4fae93aae11c9eb7', '2b203b252af51fe1878657bbf0dfefed275109b8e66caddf4caa83bc9e9b2089', 'a07a4cf93e6f65a03de1da239edfea35d04d76855d2567849175885505714d1f', 'd225cac328291d3e79e7fb5dc4567b17c9fe838a2b787efe75a79e6c6f2d18ee',
  '1d5d5d510f453411565e1e436219ac72e2b8b15c5dcf363752ee5df81dd48e2f', '5a5f14071f7aa3a61dc62a24b4cc298fbbbc959b7dced57616b3f5cf40d458d5', 'c8c1310522e4502c4140b201380ce9ae67763070801a18612febe520f6089d5f', '0b29d2e74a9a2fb6bda125a675518f51ae0f341daf5fb42fb3004dd97a2eaad6',
  'afde582681a83906e060ebd4311f7d1ab55437a2530e0942ed857a9d076ac610', '2f77c28fb36c65541e87785be526c779521154763d87e31b44af4e2e07150435', '8224a46d6b9f24b851bbb14d5a958411ffc9ec9e5a1f6fdc3143a8e9a1d10002', 'ea780ea9c83560fd92041483bc1247d7005e2ec875e0c34979cb518d821db796',
  '7023a9ba1d619e848c247790c2815fab3a0ba6cf60ca3808a584dec1a7a0a3a4', '17601bcb20e5fc57ac1fb5ab0d889f4a284ca2b644f4c216fd1621663b208f6b', 'f4b78a29bb509dfdadd22dbfcb95433283270a328f1af1fa59e78c144aa1051e', '0f4d5dc2791f8ebd29197d66e658c5d2b5817fcfd6474b1c86a1fdd024f58f8d',
  'bffaf3050564182ae962dabe26b6dfad89e0b09925e2fb6de991cac79f6958a2', '671d7abecd858cc962c08b45ae09f54cfb34d75ed7211ef620c8d6ac8dbdd695', '3666a8e217e626a87283ee6ff653a9ac394a2fc979937d8bb141cb4a12b6c781', 'e3192044a056c7933ab62e69becf2d5e4a85c87e8efdad332240524c7d832b76',
  '43d86e66ebd452f634e489da5869b2f5de0b471527330f64aa2c43ac9edb282b', '9aae478d44df7ece758d92070ec859e4603db5ed94408de489f44ae031759499', 'd4e3665b83133e381b0b245a20d9dba5e610aecc403cb22fb517e5ad34f6392c', '95d2a10c48dea2b0285d37825c5fe62bef7dbd952fa4a8ab91f81773a790ef61',
  '6e92abc4e798377c7b86ba0cc46c72fe2d1d369ec544a90709606d04fccd5a25', '67edac6010f1abd4f7855d118cb26207313cf83e2e476400af79de319a2141a5', 'e540d2a8ea057cdefd528a910a4d136517b2cc85477eb7be29096e1438d05eea', '48b9ea9bd10495ec085a56842dd83dd486c69769123df3a82d4ebdde6733fa49',
  'fd01b600bd1bc6fc2e0fb3223582e61879b54f3fd70c8dfa8605c3763c6b5196', '93738674f795c113c9fae997b0ef0f1d212395f17660028fa86f411adeb94ee8', 'd23c5c3710bd8b5aecdd6626f93b435d406bcf9c23759d0fb6556528ac93da45', 'fdfc12b877c14ca673d9d72a9ed53f6bc01c906b32e6d4da55255b09cfaa4414',
  '78a1f6f7cb5a0943589ad29c795e63f0f40ae6695488d6bd45a2b1e7e225b23a', 'ad8b138b437216c34384fe0722cd19b0813f3ccf2c504bfd735e635ebc65bea5', 'ac75f7c6d3cf8d68f23fbd5555d4c107bd7f76a3d376cd27bb943e940c2b94a1', '13bac5393f638e24fff0b60316176f5c0a80e9ed99fb06fdab2f29ed351eab54',
  '4d8d5852eddf9a8491a0483d5b6a3d7990304dd2d29a3da925a416a177021b9c', '656e1933cb4d01cf40f6fd2f5fe3ae7f8b62e941dd788a37e656dc03c376e7cb', '08b8b444db3da0e1a933d988893a59d5a6f52c59c7fd083f2f0e0271192c28a4', 'f4b9fc4277748267865653eb8a0de1f8baf8289ddb91e2744578e1b2fa8203f5',
  '4d1f3d56c628f13d64c2ca6ee8c3aac74aaced7fa3921ffd47ce433093e3b4a5', 'ee4a5af7cc7f56dce1646b122eeb53eaa785a8d9fb7fc5786c3889d4f4670823', '5827d6edbe8c065b011f14781ae45175ad0c90316c2e5c5fb1844e3629a41d70', '78b91b30ae435212f9d3a269ede62202a2aa0413e17ea15ca8396eb744211de7',
  '98396a3cebda3fa2c4084763fc2827335b3a346bf0297b97ca45cd0d8ce66b81', 'c10c05db379f74fdc4cc5676be82d3ac24045859618c9825f533b955da87e014', 'a0b6675b5585e4aed34de35df2e626a8599e3cc3fc29a101b6bcc67a42f9b7e7', '33e5505e080016f510f63b7041947c2df57e850fe4df94f970132363a620c3ae',
  'ad9c2094109bc9e43bb44168ad84c3fde01bfd76eb4aba42b3bb63050c410d6f', '4c105aa95e90c12eb991e84a547a8d07a823937d4278b33009c056e71c8eedc8', '8cfaddb8e957c4b2377e047506df66b0e1e8ab78053f274c07d3fea0887155db', '7418bfc6e473cc53574e50c8900357edf2b01c1878871dd3a6826a00d356e885',
  'ff78c051d6bfc28a9ff460646365575f8249eedf059be9a98851b69cd3a14c1f', '065f0159693055717a4bb1ca8d8dae3ad2a328d189873ff0f3ef5ecdc789010f', '31f0c30dff498b39030650427e2b5ad498cca2134ecad20af3b3a7484b6738a4', '570787ae66fc88a3c246e2283cf3c036353862338794f6cfa02e073b09f4afd9',
  '9b6b68a32ec5ecec37ff196d26a3f11ade638d8ae951b514ae2a1eb49cfa35eb', '98ccc0816de0e9d997bfac70ba0be901f78eda5208b4bdb35357c0ebbc4d0cf1', '76a3ea044b2326dab9ca288720d87c295c275a22c21a31d57d0ea97db4e7fc44', 'cb61ec808ac90e75d708a190edc52998f89cac1d3e3fa935d93b85c7b4fbad14',
  'a1291bd0d59f89cf81c6a87bfcb222ad316e2fbeb572f32074ba398c5fadfa0e', 'b3de6f72921818b0b87e385a4a990b8721cc48e4090df410d7d0805c805e4f03', '002138d0e83c245d264e0c0a502c7b55560f1eacdbac0b49f0f7154e1684f752', '4c88904171ff9392043bcbe3efd667e097d87d3169bfce26bf77600b8f5b7ae3',
  '6815f54a8fa1204328747b213500ead062517b16744013fa0718e6606cbb5464', '2f50c940d1b71d82a931b28c1ae51b063200de29c1795cef0cb161dcd6447fd4', '63d75d1c462fd11e32b2721d0b36a22532d7ba6cee71b67dbcef704df81bdfdf', '43ff2f01e775f5940105d7e6f88b37290f58cc16dfbb319ad095b375822830ab',
  '1ca204f160a3dc4975c5e6ecf84fd08d4e66efd9bb9c5ee693b9d797874c0487', '732638d80f4aa7eaa6eca255a3ab791644e4b1fab50ee3bb1ee4ffbd09b81074', 'b41f7b9b69505127ede886c04c7e36ecadc8ff36ee3fbc2dadbb00bdf405b77a', '56894b6a33f729e565dfb5a825a09c75df10cf5f13cda967c2fb1e342d0bd81c',
  '458f266e9cff6fa8f3fa576aa492c78bdc4f9edf10ec488b60c2b86dc675a9df', '163f5c2b962db1d5cb245425fc3bcff333f8819677fb52225ff01b87be8eb114', '90d270a2f1d5d767b52f6f6a51603be907f5b860274e9b17e4f1e01eeb50b9d9', 'b29dd3709b8d9d634892f4335bd51ca2e7f0e7c867bb8165c89b634227ebfada',
  'b62c60d8f151339171364e6cfbe048a3538d2209a867f052f9344518704f5c2e', '843f29b3af108b6da2f55a6277d1486b740a96b0b2c271b102139387481751b1', 'f6ac314fdc61818260a67b39a5b3abeb750bf0d96e42e45e882d81e399c4e812', '95921928909ac73d34a04a9d9679ea08b3f3bf1ead7baee7e09a5e37f2c419dd',
  '1fd0c03d637a145a3cf95f1fd430c0b1eb019d1265f64ef7d438de078f9879ed', 'bae8f0244f58aefe2ded8da7b6f900d5768f06e4b4d661ffae71bd9b723386e8', '016379bf2df13f6f24af061a41f1ea5c154948b58d5867ec728974a8a3363ba5', 'b2db99c3ee2292c81649d0ab9ba7abb7950a6fdd9964c99322e3fe815e3d5e79',
  '01da8d101372ffac46a36270d62c289cd40332a009f984900e1be3da220e2ab9', 'f7f2c9780c6dba0cc8f6dfdeb36f3f6a4dd557063b81681c153044c9babd8a9e', 'd27fd2b3625dcfea7dcc436fb4fe882d8311872181e8905b1f21a087d278962f', 'f458b5a7ecd81d4abe843d46d2b73aa4fe0984daedd6165e81d5b1a27babeded',
  '8a647ca02b41eee23c5c666a9597ca7c302daf2c40c033737abcadce8fdd6525', '959db83a2e9b01f674e5ac18432c89d658a607b45416b5dda73b6d7905095ca0', '61caca5461d227b0f1ced6c19a33c727379260ad3e1d143c7fdecb0585a4430b', '54725b27a89937637c19733a9187d7f9ee0a2b643cff9c4f96f8ab4cf8d984de',
  '2f09e83d7bee5e924e9a55af9c3fabd61d8152c5a33967bc911d11cedfd507c3', '38e251775ec585943b91a3dc28ff8e80d4ab9e0c7c7150affe6052e5a9bf1e9f', '39bf76bf5bd8455723ebb00a7d7de7758f429f4450e9d138adfaf72e29f7d5ad', '575ecd2b0bf47d0701163f85f4768a50ef29c11a0f5d6683effb65d31696ee01',
  'fb60486e7b314432f893a03dfa454fb20d3c3e6c60269c73e2907baaf6e45db6', '8109d88057a207e860edd71e25b571015c2dd7a7610dcaa7c250ec225d389634', '916887251ad97e799d54c82046b68713a421a74f28f042a367054b6e169c495a', '0465b42a786e227ffa08e8d648c03a142b281bf391aa6603e703d7217a12e864',
  '601aa0da70d989530099c63f21bd65dd51be2af13c8185fb46c9d1a3600532ca', '8acf2c92ea55935814a56ca2a643d1ef401de07d19fc221cee183fb2b50cd876', '071be80af763adce9c6369197a6d75522d3c99fdaef255ed8b9343f20b1c4129', '395b897ce8020243e94da3836f0715297b02bad08ce2148d366c698da5ed620a',
  '3c93240d58fe6cded535559a5b43c97938d81a37c95d72c54d198c03b72135d4', 'e86e61b37c3891775c2d8dc45a48f8ce6c0a12b72a127c36ca8e0214b6ef4ec1', 'f31fcc22538c1b5ea9e106e22c325c926c3ff51c97a3739d3778b641d6733809', '867db436204fc93857c3d9903cf2f2c0657c4ef785263f4823c98af49fddfb3a',
  '83b71931710c9456034eb1f4877617f41418309116ab6603bf294b57dd651152', 'c4c5129ccf0ebd60271e8c1763ba87daaa2bcfc00e24dc7d97940d021acc12cb', '3de58eb0880652c9998b2c9e89da1e8e6f37a34f212bbe73a61ceb7b98c2c8e8', 'a8ae9543c7086b39c5338f5243d438bd359ae1b3c8d80a669c5985d2f00f8f14',
  '0270f76b3ebc7b60d3217a759c4552e5220876254d11e709c2ca1457fbc8e965', '020d4a695b942aceb4e0871bf3c76c84f9fa186b3ed73a080cd1d56639346b07', '59e65974297b93e3ea89e41ee725f3b0b432c0e948f4fe67378ecf7ad8d20c83', '35d56d9eb27593a5d03120d2aead730712bde68d42f290f4383750f6930eaa05',
  'fa9f8419f95e085714c9063174ad0b9440fd988053251eaa9dd049b96308dedf', '8f3418b99b5233691c14ca0996bdbca44ad87831ef13de0463c50c86925b8566', '8ecfaf3d57bb08e93a1d1ff19c9d15ba21f2bf0ecafa1dd9b96ff01f81f3e4c3', '5abdd857ca7b37550a3cd4145e436ded6eab528d1ebe173cee1d18bee56c45f2',
  '1ef413de87f840fc1947a71f6675fbd2f041a5fd2a2e2360e390cb00dc93ba61', '1f334bed4e2c1657570c0beb760b018821ad6e85d804f4d8cf6417c69243c079', '35c7a627c904ae2d33e1ccab5dc8edaad7e46a62df3e80c0e58e59e843090c1c', 'aa96bb75b96f3d40bf6d382dcadaa28a43a995b9a667394e6a11324b124e5d77',
  '0b166501f892eeded04be155dbdbe7d6491ea8e76f9fcefe1caca757a1cf7dce', '6524f2a7df26556b588d4889e05369eba2856c94da5b9f49319430e25f6d2290', '677cc153b3face14ae089b0854e68218caf3d7deeea49a89f7f2a0423972bf2f', '26ee64f6af0e387238649513495ad17f85766623bfeec8dafe74d654831d9689',
  '734dafed95dbf639e788c94078f35c099c5ceb969024c72cff16fd2cfc50932f', '63e5defdd7296fe117ccf304b7e58af954571b37c022a12023fa0ec9c02bd2b0', '973128e7a03a63917fbb3d742ae440656fa4f2bdf4634d9baa73856f079880fa', 'b54bebeb7ef1fcd3fcc5e6914ba9507c7644b661c3ada58fcb506d5c1bb22b13',
  'f4a3a9d1134d8d85ecd5c745d434745a878345fa6d990307fdd0e818a56c3da2', 'b3bf0cd29d70cda6e549787c2cd76712588c41b767a33e948fa138e2b755b60e', 'b02bc654171a89d1c0f467eb1ae160091308814796013e7a6ddd2349f1ca18af', 'dce600e1a7d403cb45bd78a2ed70085f48a143b1e022457dc64fb5a636bdddda',
  'bbb654194c5d0f474fbbcb6d46e1cef5bcc8c2c190d2781fb4d029b121f5651b', '505d1cab24797e52c47a7b0126d5ead9d45d0b2e43deff4de4c7a38b585828e1', '29f0f18ce3b1c1de707e00a9d0d3a6bc04f884dfe2285bd779666502ed762e13', '811228cb673eae8c3611fb7af614ce73799c81c197eb1126a3ada47c36bc0086',
  '7e8e30d861c64a9cbaff38b4ba78df91e8b18dce1b714f924c5b105bae29a988', 'bb1343570e28bdc5c1d5ae4a3b3ec68703afd420316a697c2d3ff4488eb4c8b9', 'fa58deeee3118f47ab669474e6bd1df737bb211a7732f6df1eb646a1d2f14850', '0c46405a416a0656dc7e00f810738eee64ddb1053903da9f721ab8678066529f',
  '36de7610159913f00028ef23a6684036fe0e7b3667845eac6067b9644450567a', '3340568246f8ab59aa6fc705fce1983f0d054bb155fd61af1f2058395edfa41f', '5323983f94aebc03694f71e38de03e680387bf5cfac3c807df473ed7d518103f', '3fb0e68d5dfc60d17d1b329809df73272ab21fe3e241c182c1400d0a9be12e9c',
  '96b7369f9ecc05ebdc744f7d4572479757d1e5623a3299e532687b3cd78fb98c', '7e9ffe830b598abdc5bd7b82928fb0813a9c6a6f56c069b3403fb4a9d03e5921', '0572a2a75c384a38e7c493624359004a01f4a25f29b9351abd089ec968f05092', 'f5aa6f928f38d1adc78558944549c5aa5bda975e52f7a39c510b6d5de904fb1e',
  'bf6987b99630f99825009188aea6045dc4ad07a8e3381bdebf34346d85f74e98', '824128fc76a61ba1a9dba7cf48f762ff36b1949f82dde690c30fd98bc28c0de3', '3628e079cb4deea0255cd92d931e7cc62f4069659896b45071ab907357b0e14b', '7ac33789be2e838c7af2e148f3965fb6a9e8737fd3e28b69373df94b7ade87e4',
  '936eece0be9c11e4b345aac02a1c24e59fa61680a80d7dabe155b24a55445199', '6b0fd8895fc3f5aacae9eac3e23b9910b93738e5ac0dde6bf258ee7e92b61f02', '089a6621da5c37a167be966bf607420caf2d9c9ca2581635e0e0594bea61b1f8', '23edc878680ec55fac3b829673c33862144499c8189ac424e7ba8cf1c0a464ec',
  '8879d87f6d965a2f43d1b28210486a8c638b089de1632eb969a213a0d058623a',
};

const Set<String> _nameStandaloneDigests = <String>{
  'c7d49f46677bf59128b679826845f0c3173aa4fd0b3c2e553c6ce29e8e0ac5e5', '8bedd2ca3284519ab249de9e9f1a15e040a97a8f82e38b32116df1060714cd2d',
};

const Set<String> _phraseDigests = <String>{
  'f65a24e8f70fb5c672c87d93f1c5222638d981be1d8b354dd6bf70b1c02d122e', '7880e9199cdd90bb6515ac2532ab35fa4fb9e81976f2976a23090dc03bc729bd', '9aa39a1f827565555c9a51de1656cd6dd37284288f67b2c5e392f6d66710d147', 'cbbed9a72b429c78181e9bb70633d54ef6be27292beddb468ac86ccb07511579',
  '0335e2c12a9c82d64a4f34be6ccad4fbaf2ebe5fe8f6620f8263236e29c3ce93',
};

/// 允许出现的结构化数字：合成值 + 公开的班级编号（教务「公共查询」里的班级码，非个人信息）。
const Set<String> _okStudentNos = <String>{
  '2000000000', '2000000001', '2000000002',
  '2202300001', '2202400001',
  '2202500001', '2202500002', '2202500003', '2202500004',
  '2202500005', '2202500006', '2202500007', '2202500008',
  '2503010011', '2508090211',
};
const Set<String> _okIdCards = <String>{'110101200001010010'};
const Set<String> _okGaokaoNos = <String>{'25360000000001'};
const Set<String> _okNoticeNos = <String>{'202510000P0000'};
const Set<String> _okMacs = <String>{
  '00:11:22:33:44:55', '11:22:33:44:55:66', 'AA:BB:CC:DD:EE:FF', 'FF:EE:DD:CC:BB:AA',
  '00-11-22-33-44-55', '66-77-88-99-AA-BB',
};

/// 扫描范围：用户裁定「lib/ test/ docs/ reverse_engineering/」+ 根目录说明文档与 tool/packaging。
const List<String> _roots = <String>[
  'lib', 'test', 'docs', 'reverse_engineering', 'tool', 'packaging',
];

const Set<String> _skipDirs = <String>{
  '.git', 'build', '.dart_tool', 'app_data', 'failures',
};

const Set<String> _skipExt = <String>{
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.ttf', '.otf', '.woff', '.woff2',
  '.hive', '.lock', '.so', '.dll', '.exe', '.zip', '.gz', '.xlsx', '.docx', '.pdf',
};

String _digest(String value) =>
    sha256.convert(utf8.encode('$_salt\u001f$value')).toString();

List<File> _files() {
  final out = <File>[];
  for (final root in _roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final path = e.path.replaceAll('\\', '/');
      if (path.split('/').any(_skipDirs.contains)) continue;
      if (_skipExt.contains(path.substring(path.lastIndexOf('.')))) continue;
      // 守卫自己豁免：白名单/摘要表/注释里必然会写出这些形状与词的「反面样本」。
      if (path.endsWith('test/privacy_guard_test.dart') || path.endsWith('privacy_guard_test.dart')) {
        continue;
      }
      out.add(e);
    }
  }
  return out;
}

String _read(File f) {
  final bytes = f.readAsBytesSync();
  if (bytes.contains(0)) return '';            // 二进制
  return utf8.decode(bytes, allowMalformed: true);
}

void main() {
  final files = _files();
  final texts = <String, String>{for (final f in files) f.path: _read(f)};

  test('守卫自己别空转（扫到的文件与语料量级）', () {
    expect(files.length, greaterThan(300));
    expect(texts.values.where((t) => t.isNotEmpty).length, greaterThan(300));
    expect(_nameDigests.length, greaterThan(50));
    expect(_phraseDigests, isNotEmpty);
  });

  test('结构类：证件号 / 手机号 / 票据 / 会话 / 令牌 / 学籍号 / 学号 / 通知书号 / MAC 全为零命中', () {
    final patterns = <String, (RegExp, Set<String> Function())>{
      // 身份证（含末位 X）
      '证件号': (RegExp(r'\b\d{17}[\dXx]\b'), () => _okIdCards),
      // 手机号
      '手机号': (RegExp(r'(?<![\d.])1[3-9]\d{9}(?![\d.])'), () => <String>{
            '13800000000', '13800000001', '13800000002', '13800000003',
          }),
      // CAS 票据：TGT-<数字>-<随机串>
      'CAS-TGT': (RegExp(r'TGT-\d+-[A-Za-z0-9_-]{8,}'), () => <String>{}),
      'CAS-ST': (RegExp(r'ST-\d+-[A-Za-z0-9_-]{8,}'), () => <String>{}),
      // 会话：SESSION=<uuid> / JSESSIONID=<16 位以上>
      'SESSION': (RegExp(r'SESSION[=:]\s*[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-'), () => <String>{}),
      'JSESSIONID': (RegExp(r'JSESSIONID[=:]\s*[A-Za-z0-9]{16,}'), () => <String>{}),
      // 平台令牌
      'openId': (RegExp(r'openId=([A-Za-z0-9%+/=_-]{8,})'), () => <String>{'TESTOPENID'}),
      'cardinfo': (RegExp(r'cardinfo=([A-Za-z0-9%+/=_-]{8,})'), () => <String>{'TESTCARDINFO'}),
      // 学籍号 2016xxxxxxxx
      '学籍号': (RegExp(r'(?<![\d.])2016\d{8}(?![\d.])'),
          () => <String>{for (var i = 0; i < 10; i++) '20160000000$i'}),
      // 学号 2xxxxxxxxx（10 位）
      '学号': (RegExp(r'(?<![\d.])2\d{9}(?![\d.])'), () => _okStudentNos),
      // 考生号 14 位（排除小数：加权成绩 91.85964912280701 那种）
      '考生号': (RegExp(r'(?<![\d.])\d{14}(?![\d.])'), () => _okGaokaoNos),
      // 通知书号 20xxxxxxPxxxx
      '通知书号': (RegExp(r'20\d{2}\d{3,5}P[0-9A-Z]{4}'), () => _okNoticeNos),
      // MAC（前后都不接十六进制/分隔符，避开签名指纹那种 32 段串）
      'MAC': (RegExp(
          r'(?<![0-9A-Fa-f][:\-])(?:[0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}(?![:\-0-9A-Fa-f])'),
          () => _okMacs),
    };

    final bad = <String>[];
    patterns.forEach((label, spec) {
      final (rx, allowed) = spec;
      final ok = allowed();
      for (final entry in texts.entries) {
        for (final m in rx.allMatches(entry.value)) {
          final hit = m.group(0)!;
          if (ok.any(hit.contains)) continue;
          final line = entry.value.substring(0, m.start).split('\n').length;
          bad.add('$label  ${entry.key}:$line  →  ${hit.length > 40 ? hit.substring(0, 40) : hit}');
        }
      }
    });
    expect(bad, isEmpty, reason: '疑似真实个人信息：\n${bad.take(20).join('\n')}');
  });

  test('自由文本类：真人姓名（加盐摘要黑名单）零命中', () {
    final bad = <String>[];
    final rx = RegExp(r'[\u4e00-\u9fa5]+');
    for (final entry in texts.entries) {
      for (final run in rx.allMatches(entry.value)) {
        final s = run.group(0)!;
        for (var i = 0; i < s.length; i++) {
          for (var len = 2; len <= 4 && i + len <= s.length; len++) {
            final d = _digest(s.substring(i, i + len));
            // 两个与常用词同形的名字只在「贴到中文串边缘」时才算：
            // 「任何东西」「课程进行」是词，不是人名（glue_review.py 实测贴字处 0 命中）。
            final standalone =
                _nameStandaloneDigests.contains(d) && (i == 0 || i + len == s.length);
            if (_nameDigests.contains(d) || standalone) {
              final line = entry.value.substring(0, run.start + i).split('\n').length;
              bad.add('${entry.key}:$line  →  ${s.substring(i, i + len)}');
            }
          }
        }
      }
    }
    expect(bad, isEmpty, reason: '疑似真实姓名：\n${bad.take(20).join('\n')}');
  });

  test('自由文本类：真实地址（加盐摘要黑名单 · 8 字窗口）零命中', () {
    final bad = <String>[];
    final rx = RegExp(r'[\u4e00-\u9fa5]+');
    for (final entry in texts.entries) {
      for (final run in rx.allMatches(entry.value)) {
        final s = run.group(0)!;
        for (var i = 0; i + 8 <= s.length; i++) {
          if (_phraseDigests.contains(_digest(s.substring(i, i + 8)))) {
            final line = entry.value.substring(0, run.start + i).split('\n').length;
            bad.add('${entry.key}:$line  →  ${s.substring(i, i + 8)}…');
          }
        }
      }
    }
    expect(bad, isEmpty, reason: '疑似真实地址：\n${bad.take(20).join('\n')}');
  });

  test('抓包凭据：sessionToken / fpVisitorId / CAS execution 零命中', () {
    // 2026-09-21 第 4 轮才发现的类别：reverse_engineering/ 里存着整页抓下来的 CAS 登录页，
    // 里面夹着 sessionToken（会话令牌）与 fpVisitorId（浏览器指纹）。
    // 唯一豁免：lib/features/qr_login/.../wechat_login_remote_datasource.dart 把联邦登录 URL 连
    // 同 sessionToken 写死在代码里 —— 那是**功能常量**（学校服务侧令牌，非个人信息），
    // 动它会打断微信登录链路；已单独报给项目所有者决定，不在这里静默改。
    const String exemptPath =
        'lib/features/qr_login/data/datasources/wechat_login_remote_datasource.dart';
    final rx = RegExp(r'sessionToken(?:%3D|=)[0-9a-fA-F]{32}'
        r'|fpVisitorId"\s+value="[^"]{8,}"'
        r'|execution=[0-9a-f-]{20,}_[A-Za-z0-9_+/.=%\-]{40,}');
    final bad = <String>[];
    for (final entry in texts.entries) {
      if (entry.key.replaceAll('\\', '/').endsWith(exemptPath)) continue;
      for (final m in rx.allMatches(entry.value)) {
        final hit = m.group(0)!;
        // 合成值放行（TESTVISITORID / TESTSESSIONTOKEN / <REDACTED> 是清洗后的占位）
        if (hit.contains('TESTVISITORID') ||
            hit.contains('TESTSESSIONTOKEN') ||
            hit.contains('<REDACTED>')) {
          continue;
        }
        final line = entry.value.substring(0, m.start).split('\n').length;
        bad.add('${entry.key}:$line');
      }
    }
    expect(bad, isEmpty, reason: '疑似抓包凭据（会话令牌 / 设备指纹 / CAS execution）：\n${bad.take(20).join('\n')}');
  });

  test('脱敏后的合成值确实还在（守卫没把清洗成果一起删掉）', () {
    final all = texts.values.join();
    expect(all.contains('Test123'), isTrue, reason: '校园网/邮箱口令应已换成合成口令');
    expect(all.contains('TESTOPENID') || all.contains('TESTOPENID'), isTrue);
    expect(all.contains('110101200001010010'), isTrue, reason: '合成身份证应还在测试数据里');
  });
}
