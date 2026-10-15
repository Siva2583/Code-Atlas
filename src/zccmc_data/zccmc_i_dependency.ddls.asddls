@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Object Dependency Interface View (Proposed M1)'
define view entity ZCCMC_I_Dependency
  as select from zccmc_depend
  association [1..1] to ZCCMC_I_CustomObject as _FromObject      on $projection.FromObjectUUID = _FromObject.ObjectUUID
  association [1..1] to ZCCMC_I_CustomObject as _ToObject        on $projection.ToObjectUUID   = _ToObject.ObjectUUID
  association [0..1] to ZCCMC_I_ImportBatch  as _LastImportBatch on $projection.LastBatchUUID  = _LastImportBatch.BatchUUID
{
  key dependency_uuid    as DependencyUUID,
      from_object_uuid   as FromObjectUUID,
      to_object_uuid     as ToObjectUUID,
      source_system_id   as SourceSystemID,
      from_type          as FromType,
      from_name          as FromName,
      to_type            as ToType,
      to_name            as ToName,
      dependency_type    as DependencyType,
      evidence_source    as EvidenceSource,
      last_batch_uuid    as LastBatchUUID,
      last_source_record as LastSourceRecord,
      row_sha256         as RowSha256,
      @Semantics.systemDateTime.createdAt: true
      created_at         as CreatedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      changed_at         as ChangedAt,

      /* Associations */
      _FromObject,
      _ToObject,
      _LastImportBatch
}
