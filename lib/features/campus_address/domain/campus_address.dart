/// 学校校区信息。
class CampusInfo {
  final String name;
  final String address;
  final String postcode;

  const CampusInfo({
    required this.name,
    required this.address,
    required this.postcode,
  });
}

/// 江西财经大学四个校区的地址与邮编一览。
const campuses = <CampusInfo>[
  CampusInfo(
    name: '蛟桥园校区',
    address: '江西省南昌市昌北国家经济技术开发区双港东大街169号',
    postcode: '330013',
  ),
  CampusInfo(
    name: '青山园校区',
    address: '南昌市青山南路596号',
    postcode: '330077',
  ),
  CampusInfo(
    name: '麦庐园校区',
    address: '江西省南昌市昌北国家经济技术开发区玉屏大道665号',
    postcode: '330032',
  ),
  CampusInfo(
    name: '枫林园校区',
    address: '江西省南昌市昌北国家经济技术开发区枫林大道632号',
    postcode: '330013',
  ),
];
