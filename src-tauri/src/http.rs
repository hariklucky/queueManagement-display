use reqwest::Method;
use serde::Serialize;
use std::collections::HashMap;
use std::str::FromStr;
use std::time::Duration;

#[derive(Serialize)]
pub struct HttpResponse {
    pub status: u16,
    pub body: String,
}

#[tauri::command]
pub async fn native_http_fetch(
    url: String,
    method: Option<String>,
    headers: Option<HashMap<String, String>>,
    body: Option<String>,
) -> Result<HttpResponse, String> {
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(15))
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|error| error.to_string())?;

    let method = Method::from_str(method.unwrap_or_else(|| "GET".to_string()).as_str())
        .map_err(|error| error.to_string())?;

    let mut request = client.request(method, &url);

    if let Some(headers) = headers {
        for (key, value) in headers {
            request = request.header(key, value);
        }
    }

    if let Some(body) = body {
        request = request.body(body);
    }

    let response = request.send().await.map_err(|error| error.to_string())?;
    let status = response.status().as_u16();
    let body = response.text().await.map_err(|error| error.to_string())?;

    Ok(HttpResponse { status, body })
}
