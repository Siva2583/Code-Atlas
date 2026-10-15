@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Custom Object Interface View (Proposed M1)'
define root view entity ZCCMC_I_CustomObject
  as select from zccmc_custobj
  association [1..1] to ZCCMC_I_SourceSystem as _SourceSystem         on $projection.SourceSystemID = _SourceSystem.SourceSystemID
  association [0..*] to ZCCMC_I_UsageFact    as _UsageFacts           on $projection.ObjectUUID     = _UsageFacts.ObjectUUID
  association [0..*] to ZCCMC_I_Finding      as _Findings             on $projection.ObjectUUID     = _Findings.ObjectUUID
  association [0..*] to ZCCMC_I_Dependency   as _OutboundDependencies on $projection.ObjectUUID     = _OutboundDependencies.FromObjectUUID
  association [0..*] to ZCCMC_I_Dependency   as _InboundDependencies  on $projection.ObjectUUID     = _InboundDependencies.ToObjectUUID
  association [0..1] to ZCCMC_I_ImportBatch  as _LastImportBatch      on $projection.LastBatchUUID  = _LastImportBatch.BatchUUID
{
  key object_uuid        as ObjectUUID,
      source_system_id   as SourceSystemID,
      object_name        as ObjectName,
      object_type        as ObjectType,
      package_name       as PackageName,
      description        as Description,
      business_owner     as BusinessOwner,
      criticality        as Criticality,
      first_seen         as FirstSeen,
      last_seen          as LastSeen,
      findings_as_of     as FindingsAsOf,
      last_batch_uuid    as LastBatchUUID,
      last_source_record as LastSourceRecord,
      row_sha256         as RowSha256,
      @Semantics.systemDateTime.createdAt: true
      created_at         as CreatedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      changed_at         as ChangedAt,

      /* Associations */
      _SourceSystem,
      _UsageFacts,
      _Findings,
      _OutboundDependencies,
      _InboundDependencies,
      _LastImportBatch
}
