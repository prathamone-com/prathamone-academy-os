/**
 * LoginPage.jsx — PrathamOne Academy OS
 *
 * Premium branded login page at /login.
 * On success, redirects to /dashboard.
 * On failure, shows inline error with animated shake.
 */

import { useState, useRef, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { Eye, EyeOff, Loader2, AlertCircle, ArrowLeft, ShieldCheck } from 'lucide-react';
import { useAuth } from '../context/AuthContext';

export default function LoginPage() {
    const navigate = useNavigate();
    const { login, isAuthenticated } = useAuth();

    const [username, setUsername] = useState('');
    const [password, setPassword] = useState('');
    const [showPwd, setShowPwd] = useState(false);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const [shake, setShake] = useState(false);

    const usernameRef = useRef(null);

    // Already logged in — bounce straight to dashboard
    useEffect(() => {
        if (isAuthenticated) navigate('/dashboard', { replace: true });
        else usernameRef.current?.focus();
    }, [isAuthenticated, navigate]);

    const handleSubmit = async (e) => {
        e.preventDefault();
        if (!username.trim() || !password) return;

        setLoading(true);
        setError('');

        try {
            await login(username.trim(), password);
            navigate('/dashboard', { replace: true });
        } catch (err) {
            setError(err.message || 'Login failed. Please try again.');
            setShake(true);
            setTimeout(() => setShake(false), 600);
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="min-h-screen bg-navy flex items-center justify-center p-4 relative overflow-hidden">

            {/* Background mesh */}
            <div className="fixed inset-0 mesh-gradient opacity-20 pointer-events-none" />

            {/* Ambient glow */}
            <div className="absolute w-[600px] h-[600px] bg-gold/5 rounded-full blur-[10rem] -top-48 -right-48 pointer-events-none" />
            <div className="absolute w-[400px] h-[400px] bg-gold/5 rounded-full blur-[8rem] -bottom-24 -left-24 pointer-events-none" />

            {/* Back link */}
            <Link
                to="/"
                className="absolute top-8 left-8 flex items-center gap-2 text-[10px] font-mono uppercase tracking-widest text-gold/40 hover:text-gold transition-colors group"
            >
                <ArrowLeft size={12} className="group-hover:-translate-x-1 transition-transform" />
                Back to Home
            </Link>

            {/* Card */}
            <motion.div
                initial={{ opacity: 0, y: 32, scale: 0.97 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
                className="relative z-10 w-full max-w-md"
            >
                <motion.div
                    animate={shake ? { x: [-10, 10, -8, 8, -4, 4, 0] } : { x: 0 }}
                    transition={{ duration: 0.5 }}
                    className="bg-navy-lighter/60 backdrop-blur-2xl border border-gold/10 rounded-3xl p-10 shadow-2xl"
                >
                    {/* Brand */}
                    <div className="flex flex-col items-center gap-4 mb-10">
                        <div className="w-16 h-16 bg-gradient-to-br from-gold to-[#9A7B3A] rounded-2xl flex items-center justify-center shadow-[0_0_40px_rgba(201,168,76,0.3)]">
                            <span className="font-serif font-black text-navy text-2xl">P1</span>
                        </div>
                        <div className="text-center">
                            <h1 className="font-serif font-black text-2xl text-white tracking-tight">
                                PrathamOne
                            </h1>
                            <p className="text-[10px] font-mono uppercase tracking-[0.25em] text-gold/40 mt-1">
                                Academy OS · Secure Terminal
                            </p>
                        </div>
                    </div>

                    {/* Form */}
                    <form onSubmit={handleSubmit} className="space-y-5">

                        {/* Username */}
                        <div className="space-y-2">
                            <label
                                htmlFor="username"
                                className="block text-[10px] font-mono uppercase tracking-widest text-slate-500"
                            >
                                Username
                            </label>
                            <input
                                id="username"
                                ref={usernameRef}
                                type="text"
                                autoComplete="username"
                                value={username}
                                onChange={e => setUsername(e.target.value)}
                                required
                                disabled={loading}
                                placeholder="admin@school.edu"
                                className={`
                  w-full bg-navy-deep border rounded-xl px-4 py-3.5
                  text-white placeholder:text-slate-700 font-light text-sm
                  outline-none transition-all duration-200
                  focus:ring-2 focus:ring-gold/20 focus:border-gold/40
                  disabled:opacity-50
                  ${error ? 'border-red-500/40' : 'border-gold/10'}
                `}
                            />
                        </div>

                        {/* Password */}
                        <div className="space-y-2">
                            <label
                                htmlFor="password"
                                className="block text-[10px] font-mono uppercase tracking-widest text-slate-500"
                            >
                                Password
                            </label>
                            <div className="relative">
                                <input
                                    id="password"
                                    type={showPwd ? 'text' : 'password'}
                                    autoComplete="current-password"
                                    value={password}
                                    onChange={e => setPassword(e.target.value)}
                                    required
                                    disabled={loading}
                                    placeholder="••••••••••••"
                                    className={`
                    w-full bg-navy-deep border rounded-xl px-4 py-3.5 pr-12
                    text-white placeholder:text-slate-700 font-light text-sm
                    outline-none transition-all duration-200
                    focus:ring-2 focus:ring-gold/20 focus:border-gold/40
                    disabled:opacity-50
                    ${error ? 'border-red-500/40' : 'border-gold/10'}
                  `}
                                />
                                <button
                                    type="button"
                                    tabIndex={-1}
                                    onClick={() => setShowPwd(s => !s)}
                                    className="absolute right-3.5 top-1/2 -translate-y-1/2 text-slate-600 hover:text-slate-400 transition-colors"
                                >
                                    {showPwd ? <EyeOff size={16} /> : <Eye size={16} />}
                                </button>
                            </div>
                        </div>

                        {/* Error */}
                        <AnimatePresence>
                            {error && (
                                <motion.div
                                    key="error"
                                    initial={{ opacity: 0, height: 0 }}
                                    animate={{ opacity: 1, height: 'auto' }}
                                    exit={{ opacity: 0, height: 0 }}
                                    transition={{ duration: 0.25 }}
                                    className="flex items-start gap-2.5 p-3.5 bg-red-500/10 border border-red-500/20 rounded-xl text-red-400 text-xs font-light"
                                >
                                    <AlertCircle size={14} className="flex-shrink-0 mt-0.5" />
                                    <span>{error}</span>
                                </motion.div>
                            )}
                        </AnimatePresence>

                        {/* Submit */}
                        <button
                            type="submit"
                            disabled={loading || !username || !password}
                            className="
                w-full mt-2 py-4
                bg-gradient-to-r from-gold to-[#9A7B3A]
                text-navy font-mono font-black uppercase tracking-widest text-[11px]
                rounded-xl shadow-[0_10px_30px_rgba(201,168,76,0.2)]
                hover:shadow-[0_10px_40px_rgba(201,168,76,0.35)]
                active:scale-[0.98] transition-all duration-200
                disabled:opacity-40 disabled:cursor-not-allowed disabled:active:scale-100
                flex items-center justify-center gap-2.5
              "
                        >
                            {loading
                                ? <><Loader2 size={14} className="animate-spin" /> Authenticating…</>
                                : <><ShieldCheck size={14} /> Access Secure Terminal</>
                            }
                        </button>
                    </form>

                    {/* Demo hint */}
                    <div className="mt-8 pt-6 border-t border-gold/5">
                        <p className="text-[10px] font-mono text-slate-700 text-center leading-relaxed">
                            Demo credentials are seeded by{' '}
                            <code className="text-gold/40">db/99_demo_onboarding_seed.sql</code>
                        </p>
                    </div>
                </motion.div>

                {/* Trust badge */}
                <motion.p
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ delay: 0.6 }}
                    className="text-center mt-6 text-[9px] font-mono uppercase tracking-[0.3em] text-slate-800"
                >
                    Tenant-Isolated · JWT Secured · RLS Enforced
                </motion.p>
            </motion.div>
        </div>
    );
}
