@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Source System Interface View (Proposed M1)'
define view entity ZCCMC_I_SourceSystem
  as select from zccmc_sourcesys
{
  key source_system_id as SourceSystemID,
      description      as Description,
      is_active        as IsActive,
      @Semantics.systemDateTime.createdAt: true
      created_at       as CreatedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      changed_at       as ChangedAt
}
