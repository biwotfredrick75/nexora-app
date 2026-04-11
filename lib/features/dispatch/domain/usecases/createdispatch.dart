import 'package:dartz/dartz.dart';
import 'package:wakulima/core/network/api_result.dart';

/// Use case: Creates a new dispatch order
/// Single-responsibility — one use case per business action.
class CreateDispatch {
  // TODO: inject repository
  // final dispatchRepository _repository;
  // const CreateDispatch(this._repository);

  Future<ApiResult<void>> call(/* params */) async {{
    // TODO: implement business logic
    // 1. Validate params
    // 2. Call repository
    // 3. Return Either<Failure, Result>
    return const Right(null);
  }}
}
