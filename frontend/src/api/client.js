const API_BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:8001/api/v1";

export async function apiFetch(endpoint, options = {}) {
    const token = localStorage.getItem("token");

    const headers = {
        "Content-Type": "application/json",
        ...options.headers,
    };

    if (token) {
        headers["Authorization"] = `Bearer ${token}`;
    }

    const response = await fetch(`${API_BASE_URL}${endpoint}`, {
        ...options,
        headers,
    });

    if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.detail || response.statusText);
    }

    return response.json();
}
