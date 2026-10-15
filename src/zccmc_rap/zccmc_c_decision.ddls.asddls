@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Migration Decision Projection View (Proposed M3)'
@Metadata.allowExtensions: true
define root view entity ZCCMC_C_Decision
  provider contract transactional_query
  as projection on ZCCMC_I_Decision
{
  key DecisionUUID,
      ObjectUUID,
      RecommendedStrategy,
      FinalStrategy,
      RuleSetVersion,
      RecommendationRunID,
      Status as DecisionStatus,
      OwnerUser,
      CreatedBy,
      SubmittedBy,
      CreatedAt,
      ChangedAt,
      EvidenceSummary,
      MissingEvidence,
      MatchedRuleIDs,
      ReReviewRequired,
      VersionNo,

      /* Redirected associations */
      _AuditTrail : redirected to composition child ZCCMC_C_DecisionAudit,
      _CustomObject : redirected to ZCCMC_C_CustomObject
}
