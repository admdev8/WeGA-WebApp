$(function () {
    var url = "http://localhost:8080/exist/apps/WeGA-WebApp/api/v1/swagger.json";
    
    hljs.configure({
        highlightSizeThreshold: 5000
    });
    
    // Pre load translate...
    if (window.SwaggerTranslator) {
        window.SwaggerTranslator.translate();
    }
    window.swaggerUi = new SwaggerUi({
        url: url,
        dom_id: "swagger-ui-container",
        supportedSubmitMethods:[ 'get', 'post', 'put', 'delete', 'patch'],
        onComplete: function (swaggerApi, swaggerUi) {
            if (typeof initOAuth == "function") {
                initOAuth({
                    clientId: "your-client-id",
                    clientSecret: "your-client-secret-if-required",
                    realm: "your-realms",
                    appName: "your-app-name",
                    scopeSeparator: " ",
                    additionalQueryStringParams: {
                    }
                });
            }
            
            if (window.SwaggerTranslator) {
                window.SwaggerTranslator.translate();
            }
        },
        onFailure: function (data) {
            log("Unable to Load SwaggerUI");
        },
        docExpansion: "none",
        jsonEditor: false,
        defaultModelRendering: 'schema',
        showRequestHeaders: false
    });
    
    window.swaggerUi.load();
    
    function log() {
        if ('console' in window) {
            console.log.apply(console, arguments);
        }
    }
});