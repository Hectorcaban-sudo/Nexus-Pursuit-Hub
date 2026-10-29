/**
 * Thin HTTP wrapper for Named Credential callouts with retry on 429 and 5xx.
 * Apex cannot sleep, so retries are immediate and capped; the caller's checkpoint
 * makes a failed page resumable on the next run.
 */
public inherited sharing class NXP_HttpClient {
    public class CalloutFailureException extends Exception {
        public Integer statusCode;
    }

    @TestVisible
    private Integer maxAttempts;
    private Integer timeoutMs;

    public NXP_HttpClient() {
        this.maxAttempts = NXP_Settings.getInteger('Http_Max_Attempts', 3);
        this.timeoutMs = NXP_Settings.getInteger('Http_Timeout_Ms', 60000);
    }

    public HttpResponse get(String namedCredential, String path, Map<String, String> params) {
        return send(build('GET', namedCredential, path, params, null));
    }

    public HttpResponse post(String namedCredential, String path, String jsonBody) {
        return send(build('POST', namedCredential, path, null, jsonBody));
    }

    public static String buildQuery(Map<String, String> params) {
        if (params == null || params.isEmpty()) {
            return '';
        }
        List<String> parts = new List<String>();
        for (String key : params.keySet()) {
            String value = params.get(key);
            if (value != null) {
                parts.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(value, 'UTF-8'));
            }
        }
        return parts.isEmpty() ? '' : '?' + String.join(parts, '&');
    }

    private HttpRequest build(String method, String nc, String path, Map<String, String> params, String body) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint('callout:' + nc + (path == null ? '' : path) + buildQuery(params));
        req.setTimeout(Math.min(timeoutMs, 120000));
        req.setHeader('Accept', 'application/json');
        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }
        return req;
    }

    public HttpResponse send(HttpRequest req) {
        Http http = new Http();
        HttpResponse res;
        Integer attempt = 0;
        while (attempt < maxAttempts) {
            attempt++;
            res = http.send(req);
            Integer code = res.getStatusCode();
            if (code >= 200 && code < 300) {
                return res;
            }
            Boolean retryable = code == 429 || code >= 500;
            if (!retryable || attempt >= maxAttempts || Limits.getCallouts() >= Limits.getLimitCallouts()) {
                break;
            }
        }
        CalloutFailureException failure = new CalloutFailureException(
            'HTTP ' +
                res.getStatusCode() +
                ' from ' +
                req.getEndpoint().substringBefore('?') +
                ': ' +
                NXP_Text.truncate(res.getBody(), 500)
        );
        failure.statusCode = res.getStatusCode();
        throw failure;
    }
}
