import 'package:dartz/dartz.dart';
import 'package:wakulima/core/network/api_result.dart';

/// Use case: Creates a new purchase order
/// Single-responsibility — one use case per business action.
class CreatePurchaseOrder {
  // TODO: inject repository
  // final purchasesRepository _repository;
  // const CreatePurchaseOrder(this._repository);

  Future<ApiResult<void>> call(/* params */) async {{
    // TODO: implement business logic
    // 1. Validate params
    // 2. Call repository
    // 3. Return Either<Failure, Result>
    return const Right(null);
  }}
}
