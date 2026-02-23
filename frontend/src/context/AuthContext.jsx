/**
 * AuthContext.jsx — PrathamOne Academy OS
 *
 * Provides authentication state and actions to the entire app.
 *
 * STORAGE KEYS:
 *   localStorage['token']         — access token (read by all apiFetch helpers)
 *   localStorage['refresh_token'] — refresh token (for silent renewal)
 *   localStorage['user']          — JSON-serialised user claims
 *
 * TOKEN FLOW:
 *   1. login(username, password) → POST /api/v1/auth/login
 *   2. Stores access + refresh tokens
 *   3. Decodes JWT claims (base64 payload — no signature check needed client-side)
 *   4. On any 401, fetchWithAuth() calls refreshToken() and retries once
 *   5. logout() clears all storage and redirects to /
 */

import { createContext, useContext, useState, useCallback, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';

// VITE_API_URL already includes /api/v1 (e.g. http://localhost:8001/api/v1)
const API = (import.meta.env.VITE_API_URL || 'http://localhost:8000/api/v1').replace(/\/$/, '');
const STORAGE_TOKEN = 'token';
const STORAGE_REFRESH = 'refresh_token';
const STORAGE_USER = 'prathamone_user';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Decode the base64url payload from a JWT (client-side, no verification). */
function decodeJwt(token) {
    try {
        const base64 = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
        return JSON.parse(atob(base64));
    } catch {
        return null;
    }
}

/** Extract user object from a decoded JWT payload. */
function userFromPayload(payload) {
    if (!payload) return null;
    return {
        userId: payload.sub,
        role: payload.role || 'app_user',
        tenantId: payload.tenant_id,
    };
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
    const navigate = useNavigate();

    // Initialise from localStorage so the session survives a page refresh
    const [token, setToken] = useState(() => localStorage.getItem(STORAGE_TOKEN));
    const [user, setUser] = useState(() => {
        try { return JSON.parse(localStorage.getItem(STORAGE_USER)); } catch { return null; }
    });

    const isAuthenticated = Boolean(token && user);

    // ── persist helpers ───────────────────────────────────────────────────────

    const _persist = useCallback((accessToken, refreshToken) => {
        localStorage.setItem(STORAGE_TOKEN, accessToken);
        localStorage.setItem(STORAGE_REFRESH, refreshToken);
        const payload = decodeJwt(accessToken);
        const u = userFromPayload(payload);
        localStorage.setItem(STORAGE_USER, JSON.stringify(u));
        setToken(accessToken);
        setUser(u);
    }, []);

    const _clear = useCallback(() => {
        localStorage.removeItem(STORAGE_TOKEN);
        localStorage.removeItem(STORAGE_REFRESH);
        localStorage.removeItem(STORAGE_USER);
        setToken(null);
        setUser(null);
    }, []);

    // ── login ─────────────────────────────────────────────────────────────────

    const login = useCallback(async (username, password) => {
        // auth/login uses OAuth2PasswordRequestForm (application/x-www-form-urlencoded)
        const body = new URLSearchParams({ username, password });

        const res = await fetch(`${API}/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: body.toString(),
        });

        const data = await res.json();

        if (!res.ok) {
            throw new Error(
                typeof data.detail === 'string' ? data.detail : 'Invalid credentials',
            );
        }

        _persist(data.access_token, data.refresh_token);
        return data;
    }, [_persist]);

    // ── logout ────────────────────────────────────────────────────────────────

    const logout = useCallback(() => {
        _clear();
        navigate('/', { replace: true });
    }, [_clear, navigate]);

    // ── silent refresh ────────────────────────────────────────────────────────

    const refreshToken = useCallback(async () => {
        const stored = localStorage.getItem(STORAGE_REFRESH);
        if (!stored) { logout(); return null; }

        const res = await fetch(`${API}/auth/refresh`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ refresh_token: stored }),
        });

        if (!res.ok) { logout(); return null; }

        const data = await res.json();
        _persist(data.access_token, data.refresh_token);
        return data.access_token;
    }, [_persist, logout]);

    // ── fetchWithAuth — use this in components that need auth ─────────────────
    // Automatically injects Bearer token and retries once on 401.

    const fetchWithAuth = useCallback(async (path, options = {}) => {
        const currentToken = localStorage.getItem(STORAGE_TOKEN);
        const go = (t) =>
            fetch(`${API}${path}`, {
                ...options,
                headers: {
                    'Content-Type': 'application/json',
                    ...(options.headers || {}),
                    ...(t ? { Authorization: `Bearer ${t}` } : {}),
                },
            });

        let res = await go(currentToken);

        if (res.status === 401) {
            const newToken = await refreshToken();
            if (!newToken) throw new Error('Session expired. Please log in again.');
            res = await go(newToken);
        }

        if (!res.ok) {
            const err = await res.json().catch(() => ({ detail: 'Request failed' }));
            throw new Error(typeof err.detail === 'string' ? err.detail : JSON.stringify(err.detail));
        }

        return res.json();
    }, [refreshToken]);

    // ── auto-expire: check token expiry AND role validity on mount ────────────

    // Canonical roles issued by the current auth system.
    // Any token containing a role NOT in this set is considered stale/legacy
    // and will be cleared so the user is prompted to log in again.
    const VALID_ROLES = new Set(['TENANT_ADMIN', 'ADMIN', 'TEACHER', 'STUDENT', 'FINANCE_CLERK', 'EXAMINER', 'ADMISSION_OFFICIAL', 'app_user']);

    useEffect(() => {
        if (!token) return;
        const payload = decodeJwt(token);
        if (!payload) { _clear(); return; }

        // Force re-login if role is a legacy alias (e.g. 'principal_admin')
        if (payload.role && !VALID_ROLES.has(payload.role)) {
            console.warn(`[Auth] Stale token detected (role="${payload.role}"). Clearing session.`);
            _clear();
            return;
        }

        if (!payload.exp) return;
        const msUntilExpiry = payload.exp * 1000 - Date.now();
        if (msUntilExpiry <= 0) {
            refreshToken();
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [token]);

    return (
        <AuthContext.Provider value={{ token, user, isAuthenticated, login, logout, fetchWithAuth }}>
            {children}
        </AuthContext.Provider>
    );
}

/** Hook — call in any component to access auth state/actions. */
export function useAuth() {
    const ctx = useContext(AuthContext);
    if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
    return ctx;
}

export default AuthContext;
