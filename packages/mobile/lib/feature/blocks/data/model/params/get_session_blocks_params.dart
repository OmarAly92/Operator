import 'package:equatable/equatable.dart';

class GetSessionBlocksParams extends Equatable {
  final int? afterSeq;
  final int? beforeSeq;
  final int? limit;

  const GetSessionBlocksParams({this.afterSeq, this.beforeSeq, this.limit});

  Map<String, dynamic> toJson() => {
    if (afterSeq != null) 'afterSeq': afterSeq,
    if (beforeSeq != null) 'beforeSeq': beforeSeq,
    if (limit != null) 'limit': limit,
  };

  @override
  List<Object?> get props => [afterSeq, beforeSeq, limit];
}
