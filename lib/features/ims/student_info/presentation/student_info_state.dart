import 'package:smarter_jxufe/features/ims/student_info/domain/user.dart';

/// 学生信息页面的 UI 状态。
sealed class StudentInfoState {
  const StudentInfoState();
}

class StudentInfoLoading extends StudentInfoState {
  const StudentInfoLoading();
}

class StudentInfoLoaded extends StudentInfoState {
  final User user;
  const StudentInfoLoaded(this.user);
}

class StudentInfoError extends StudentInfoState {
  final String message;
  const StudentInfoError(this.message);
}
