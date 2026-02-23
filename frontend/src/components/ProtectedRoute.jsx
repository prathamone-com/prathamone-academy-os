/**
 * ProtectedRoute.jsx
 *
 * Wraps any route that requires authentication.
 * If the user is not authenticated, redirects to /login.
 */
import { Navigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function ProtectedRoute({ children }) {
    const { isAuthenticated } = useAuth();

    if (!isAuthenticated) {
        return <Navigate to="/login" replace />;
    }

    return children;
}
