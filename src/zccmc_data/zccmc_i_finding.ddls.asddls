@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'ATC / Code Finding Interface View (Proposed M1)'
define view entity ZCCMC_I_Finding
  as select from zccmc_finding
  association [1..1] to ZCCMC_I_CustomObject as _CustomObject    on $projection.ObjectUUID    = _CustomObject.ObjectUUID
  association [0..1] to ZCCMC_I_ImportBatch  as _LastImportBatch on $projection.LastBatchUUID = _LastImportBatch.BatchUUID
{
  key finding_uuid       as FindingUUID,
      object_uuid        as ObjectUUID,
      source_system_id   as SourceSystemID,
      object_type        as ObjectType,
      object_name        as ObjectName,
      finding_id         as FindingID,
      check_id           as CheckID,
      category           as Category,
      severity           as Severity,
      message            as Message,
      source_reference   as SourceReference,
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
