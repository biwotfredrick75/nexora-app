import 'package:dartz/dartz.dart';
import 'package:wakulima/core/network/api_result.dart';

/// Use case: Retrieves all registered farmers
/// Single-responsibility — one use case per business action.
class GetFarmers {
  // TODO: inject repository
  // final farmersRepository _repository;
  // const GetFarmers(this._repository);

  Future<ApiResult<void>> call(/* params */) async {{
    // TODO: implement business logic
    // 1. Validate params
    // 2. Call repository
    // 3. Return Either<Failure, Result>
    return const Right(null);
  }}
}
