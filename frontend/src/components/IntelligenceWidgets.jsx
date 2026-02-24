import { useState, useEffect } from 'react';
import { apiFetch } from '../api/client';
import { Users, CreditCard, FileText, Trophy, ArrowUpRight, Loader2 } from 'lucide-react';

const iconMap = {
    Users: Users,
    CreditCard: CreditCard,
    FileText: FileText,
    Trophy: Trophy
};

const IntelligenceWidgets = () => {
    const [widgets, setWidgets] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    const fetchMetrics = async () => {
        try {
            const data = await apiFetch('/dashboard/metrics');
            setWidgets(data);
            setLoading(false);
        } catch (err) {
            setError('Failed to sync intelligence stream.');
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchMetrics();
        // Auto-refresh every 60 seconds
        const interval = setInterval(fetchMetrics, 60000);
        return () => clearInterval(interval);
    }, []);

    if (loading) {
        return (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
                {[1, 2, 3, 4].map(i => (
                    <div key={i} className="premium-card p-8 h-48 animate-pulse bg-navy-lighter/20 border-gold/5">
                        <div className="h-4 w-24 bg-gold/10 rounded mb-6"></div>
                        <div className="h-10 w-16 bg-gold/20 rounded mb-4"></div>
                        <div className="h-3 w-32 bg-gold/5 rounded"></div>
                    </div>
                ))}
            </div>
        );
    }

    if (error) {
        return (
            <div className="p-10 premium-card border-red-500/20 text-red-400 font-mono text-xs flex items-center justify-center gap-4">
                <div className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></div>
                {error}
            </div>
        );
    }

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
            {widgets.map((w) => {
                const Icon = iconMap[w.icon] || Users;
                const colorClass = 
                    w.color === 'teal' ? 'text-teal-bright' :
                    w.color === 'rose' ? 'text-rose-500' :
                    w.color === 'blue' ? 'text-blue-400' :
                    'text-gold';
                
                const borderColor = 
                    w.color === 'teal' ? 'hover:border-teal-bright/30' :
                    w.color === 'rose' ? 'hover:border-rose-500/30' :
                    w.color === 'blue' ? 'hover:border-blue-400/30' :
                    'hover:border-gold/30';

                return (
                    <div key={w.code} className={`premium-card p-8 relative overflow-hidden group transition-all duration-500 border-gold/10 ${borderColor}`}>
                        {/* Shimmer Effect */}
                        <div className="absolute inset-0 bg-gradient-to-tr from-transparent via-gold/5 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-1000"></div>
                        
                        <div className="flex items-center justify-between mb-8 relative z-10">
                            <div className={`p-4 rounded-xl bg-navy-deep border border-gold/5 ${colorClass} group-hover:scale-110 transition-transform`}>
                                <Icon size={24} />
                            </div>
                            <div className="text-[10px] font-mono font-black text-gold/30 group-hover:text-gold/50 transition-colors uppercase tracking-[0.2em] flex items-center gap-2">
                                live <ArrowUpRight size={10} />
                            </div>
                        </div>

                        <div className="relative z-10">
                            <h3 className="text-slate-400 font-mono text-[10px] uppercase tracking-[0.2em] mb-2">{w.label}</h3>
                            <div className="flex items-baseline gap-2">
                                <span className={`text-4xl font-serif font-black tracking-tighter ${colorClass}`}>
                                    {w.type === 'SUM' ? '₹' : ''}
                                    {w.value.toLocaleString(undefined, { maximumFractionDigits: (w.type === 'AVG' ? 1 : 0) })}
                                </span>
                            </div>
                            <div className="mt-4 flex items-center gap-2">
                                <span className="w-1.5 h-1.5 rounded-full bg-teal-bright animate-pulse"></span>
                                <span className="text-[9px] font-mono text-gold/20 uppercase tracking-widest">Registry Sync Active</span>
                            </div>
                        </div>
                    </div>
                );
            })}
        </div>
    );
};

export default IntelligenceWidgets;
