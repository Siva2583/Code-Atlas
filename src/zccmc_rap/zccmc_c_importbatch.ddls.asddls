@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Import Batch Projection View (Proposed M3 D03/D04)'
@Metadata.allowExtensions: true
define view entity ZCCMC_C_ImportBatch
  as projection on ZCCMC_I_ImportBatch
{
  key BatchUUID,
      FileKind,
      Status,
      FileSha256,
      Actor,
      CreatedAtUtc,
      ParsedCount,
      AcceptedCount,
      RejectedCount
}
