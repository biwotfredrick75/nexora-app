import 'package:dartz/dartz.dart';
import 'package:wakulima/core/network/api_result.dart';

/// Use case: Records a milk collection entry
/// Single-responsibility — one use case per business action.
class RecordCollection {
  // TODO: inject repository
  // final collectionRepository _repository;
  // const RecordCollection(this._repository);

  Future<ApiResult<void>> call(/* params */) async {{
    // TODO: implement business logic
    // 1. Validate params
    // 2. Call repository
    // 3. Return Either<Failure, Result>
    return const Right(null);
  }}
}
