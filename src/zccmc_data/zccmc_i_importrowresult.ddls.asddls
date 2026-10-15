@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Import Row Result Provenance View (Proposed M1)'
define view entity ZCCMC_I_ImportRowResult
  as select from zccmc_improwres
  association to parent ZCCMC_I_ImportBatch as _ImportBatch on $projection.BatchUUID = _ImportBatch.BatchUUID
{
  key batch_uuid     as BatchUUID,
  key source_record  as SourceRecord,
      file_kind      as FileKind,
      business_key   as BusinessKey,
      entity_uuid    as EntityUUID,
      result_status  as ResultStatus,
      row_sha256     as RowSha256,
      error_code     as ErrorCode,
      @Semantics.systemDateTime.createdAt: true
      created_at_utc as CreatedAtUtc,

      /* Parent Association */
      _ImportBatch
}
