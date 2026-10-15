@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Import Row Error Projection View (Proposed M3 D03/D04)'
@Metadata.allowExtensions: true
define view entity ZCCMC_C_ImportRowError
  as projection on ZCCMC_I_ImportRowError
{
  key BatchUUID,
  key SourceRecord,
      BusinessKey,
      ErrorCode,
      FieldName,
      Message
}
