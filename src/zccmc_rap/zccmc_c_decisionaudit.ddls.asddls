@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Migration Decision Audit Projection View (Proposed M3)'
@Metadata.allowExtensions: true
define view entity ZCCMC_C_DecisionAudit
  as projection on ZCCMC_I_DecisionAudit
{
  key EventUUID as AuditUUID,
      DecisionUUID,
      SequenceNo,
      EventType,
      ActorUser as Actor,
      EventTimestamp as Timestamp,
      OldStatus,
      NewStatus,
      OldStrategy as OldValue,
      NewStrategy as NewValue,
      OldOwner,
      NewOwner,
      Reason,
      RuleSetVersion,
      RecommendationRunID,
      CorrelationID,
      ImportBatchUUID,
      SoDEnabled,

      _Decision : redirected to parent ZCCMC_C_Decision
}
