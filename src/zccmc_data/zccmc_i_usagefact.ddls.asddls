@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Usage Fact Interface View (Proposed M1)'
define view entity ZCCMC_I_UsageFact
  as select from zccmc_usage
  association [1..1] to ZCCMC_I_CustomObject as _CustomObject    on $projection.ObjectUUID    = _CustomObject.ObjectUUID
  association [0..1] to ZCCMC_I_ImportBatch  as _LastImportBatch on $projection.LastBatchUUID = _LastImportBatch.BatchUUID
{
  key usage_uuid         as UsageUUID,
      object_uuid        as ObjectUUID,
      source_system_id   as SourceSystemID,
      object_type        as ObjectType,
      object_name        as ObjectName,
      period_start       as PeriodStart,
      period_end         as PeriodEnd,
      last_executed      as LastExecuted,
      run_count          as RunCount,
      evidence_source    as EvidenceSource,
      evidence_as_of     as EvidenceAsOf,
      last_batch_uuid    as LastBatchUUID,
      last_source_record as LastSourceRecord,
      row_sha256         as RowSha256,
      @Semantics.systemDateTime.createdAt: true
      created_at         as CreatedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      changed_at         as ChangedAt,

      /* Associations */
      _CustomObject,
      _LastImportBatch
}
