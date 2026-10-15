@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Import Batch Interface View (Proposed M1)'
define root view entity ZCCMC_I_ImportBatch
  as select from zccmc_impbatch
  composition [0..*] of ZCCMC_I_ImportRowError  as _RowErrors
  composition [0..*] of ZCCMC_I_ImportRowResult as _RowResults
{
  key batch_uuid         as BatchUUID,
      file_kind          as FileKind,
      status             as Status,
      file_sha256        as FileSha256,
      actor              as Actor,
      @Semantics.systemDateTime.createdAt: true
      created_at_utc     as CreatedAtUtc,
      parsed_count       as ParsedCount,
      accepted_count     as AcceptedCount,
      inserted_count     as InsertedCount,
      updated_count      as UpdatedCount,
      unchanged_count    as UnchangedCount,
      rejected_count     as RejectedCount,
      file_error_code    as FileErrorCode,
      file_error_message as FileErrorMessage,

      /* Compositions */
      _RowErrors,
      _RowResults
}
