import 'package:equatable/equatable.dart';

class GetSessionBlocksParams extends Equatable {
  final int? afterSeq;
  final int? beforeSeq;
  final int? limit;
  final String? agentId;

  const GetSessionBlocksParams({this.afterSeq, this.beforeSeq, this.limit, this.agentId});

  Map<String, dynamic> toJson() => {
    if (afterSeq != null) 'afterSeq': afterSeq,
    if (beforeSeq != null) 'beforeSeq': beforeSeq,
    if (limit != null) 'limit': limit,
    if (agentId != null && agentId!.isNotEmpty) 'agentId': agentId,
  };

  @override
  List<Object?> get props => [afterSeq, beforeSeq, limit, agentId];
}
