@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Migration Decision Append-Only Audit Entity (Proposed M3)'
define view entity ZCCMC_I_DecisionAudit
  as select from zccmc_decaudit
  association to parent ZCCMC_I_Decision as _Decision on $projection.DecisionUUID = _Decision.DecisionUUID
{
  key event_uuid            as EventUUID,
      decision_uuid         as DecisionUUID,
      sequence_no           as SequenceNo,
      event_type            as EventType,
      actor_user            as ActorUser,
      event_timestamp       as EventTimestamp,
      old_status            as OldStatus,
      new_status            as NewStatus,
      old_strategy          as OldStrategy,
      new_strategy          as NewStrategy,
      old_owner             as OldOwner,
      new_owner             as NewOwner,
      reason                as Reason,
      ruleset_version       as RuleSetVersion,
      recommendation_run_id as RecommendationRunID,
      correlation_id        as CorrelationID,
      import_batch_uuid     as ImportBatchUUID,
      sod_enabled           as SoDEnabled,

      /* Parent Association */
      _Decision
}
