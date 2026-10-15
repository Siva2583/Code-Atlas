@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Custom Object Projection View (Proposed M3)'
@Metadata.allowExtensions: true
define root view entity ZCCMC_C_CustomObject
  provider contract transactional_query
  as projection on ZCCMC_I_CustomObject
{
  key ObjectUUID,
      SourceSystemID,
      ObjectName,
      ObjectType,
      PackageName,
      Description,
      BusinessOwner,
      Criticality,
      FirstSeen,
      LastSeen,
      FindingsAsOf
}
