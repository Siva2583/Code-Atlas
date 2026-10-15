@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Import Row Error Interface View (Proposed M1)'
define view entity ZCCMC_I_ImportRowError
  as select from zccmc_improwerr
  association to parent ZCCMC_I_ImportBatch as _ImportBatch on $projection.BatchUUID = _ImportBatch.BatchUUID
{
  key batch_uuid     as BatchUUID,
  key source_record  as SourceRecord,
      file_kind      as FileKind,
      business_key   as BusinessKey,
      error_code     as ErrorCode,
      field_name     as FieldName,
      message        as Message,
      @Semantics.systemDateTime.createdAt: true
      created_at_utc as CreatedAtUtc,

      /* Parent Association */
      _ImportBatch
}
