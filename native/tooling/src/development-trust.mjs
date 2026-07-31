export const verticalSliceDevelopmentIdentity = Object.freeze({
  packageID: "vertical-slice-development-v1",
  keyID: "vertical-slice-development-key-v1",
  trustDomain: "the-long-west-vertical-slice-development-v1",
  receiptKind: "long-west-vertical-slice-development-receipt-v1",
  projectionAuthorityKind: "DEVELOPMENT_BLUEPRINT_PROJECTION_AUTHORITY",
  projectionAuthorityStatus: "CODEX_PROVISIONAL_NON_SHIPPING_BLUEPRINT_PROJECTION",
  projectionAuthority: "codex-local-production",
  shippingState: "PROHIBITED",
});

export const chapter01ImmersiveReviewIdentity = Object.freeze({
  packageID: "first-farmers-3d-review-v1",
  keyID: "chapter-01-immersive-review-key-v1",
  trustDomain: "the-long-west-chapter-01-immersive-review-v1",
  receiptKind: "long-west-chapter-01-immersive-review-receipt-v1",
  shippingState: "PROHIBITED",
});

export function isDevelopmentOnlySigningKeyID(value) {
  return value === verticalSliceDevelopmentIdentity.keyID
    || value === chapter01ImmersiveReviewIdentity.keyID
    || (typeof value === "string"
      && (value.startsWith("vertical-slice-development-")
        || value.startsWith("chapter-01-immersive-review-")));
}
