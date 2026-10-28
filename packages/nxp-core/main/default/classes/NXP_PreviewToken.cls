/**
 * Short-lived tokens that prove a preview was shown to this user today before an action runs.
 * The assistant's Save Search and Push actions refuse to act without the token returned by the
 * matching preview action, so the model cannot skip the preview-and-confirm step.
 */
public inherited sharing class NXP_PreviewToken {
    public static String issue(String scope, String subject) {
        return sign(scope, subject, Date.today());
    }

    /** Accepts tokens issued today or yesterday (covers a conversation that crosses midnight). */
    public static Boolean verify(String scope, String subject, String token) {
        if (String.isBlank(token)) {
            return false;
        }
        return token == sign(scope, subject, Date.today()) || token == sign(scope, subject, Date.today().addDays(-1));
    }

    private static String sign(String scope, String subject, Date day) {
        String message = scope + '|' + subject + '|' + UserInfo.getUserId() + '|' + String.valueOf(day);
        Blob key = Blob.valueOf(UserInfo.getOrganizationId() + NXP_Settings.getString('Preview_Token_Salt', 'nxp'));
        return EncodingUtil.convertToHex(Crypto.generateMac('hmacSHA256', Blob.valueOf(message), key)).left(32);
    }
}
