@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Migration Decision Root Entity (Proposed M3)'
define root view entity ZCCMC_I_Decision
  as select from zccmc_decision
  composition [0..*] of ZCCMC_I_DecisionAudit as _AuditTrail
  association [1..1] to ZCCMC_I_CustomObject  as _CustomObject on $projection.ObjectUUID = _CustomObject.ObjectUUID
{
  key decision_uuid          as DecisionUUID,
      object_uuid            as ObjectUUID,
      recommended_strategy   as RecommendedStrategy,
      final_strategy         as FinalStrategy,
      ruleset_version        as RuleSetVersion,
      recommendation_run_id  as RecommendationRunID,
      status                 as Status,
      owner_user             as OwnerUser,
      created_by             as CreatedBy,
      submitted_by           as SubmittedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at             as CreatedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      changed_at             as ChangedAt,
      evidence_summary       as EvidenceSummary,
      missing_evidence       as MissingEvidence,
      matched_rule_ids       as MatchedRuleIDs,
      re_review_required     as ReReviewRequired,
      version_no             as VersionNo,

      /* Compositions & Associations */
      _AuditTrail,
      _CustomObject
}
