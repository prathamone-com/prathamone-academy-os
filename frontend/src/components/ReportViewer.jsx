import React, { useState, useEffect } from 'react';
import { apiFetch } from '../api/client';
import { Table, Filter, Download, Loader2, RefreshCw, AlertCircle } from 'lucide-react';

/**
 * ReportViewer.jsx
 * 
 * Declarative report viewer. Renders filters and results based on metadata.
 * LAW 9: No raw SQL — metadata driven only.
 */
const ReportViewer = ({ reportCode, onNotify }) => {
    const [metadata, setMetadata] = useState(null);
    const [filters, setFilters] = useState({});
    const [results, setResults] = useState(null);
    const [loading, setLoading] = useState(true);
    const [running, setRunning] = useState(false);
    const [error, setError] = useState(null);

    useEffect(() => {
        async function fetchMetadata() {
            try {
                const data = await apiFetch(`/reports/${reportCode}`);
                setMetadata(data);

                // Initialise filters
                const initial = {};
                data.filters.forEach(f => {
                    if (f.default_value) initial[f.attribute_code] = f.default_value;
                });
                setFilters(initial);
            } catch (err) {
                setError(err.message);
            } finally {
                setLoading(false);
            }
        }
        fetchMetadata();
    }, [reportCode]);

    const runReport = async (isExport = false) => {
        setRunning(true);
        try {
            const data = await apiFetch('/reports/run', {
                method: 'POST',
                body: JSON.stringify({
                    report_code: reportCode,
                    filters,
                    export: isExport
                })
            });

            if (isExport) {
                onNotify?.("Report export started. Check security logs.", "success");
            } else {
                setResults(data);
            }
        } catch (err) {
            onNotify?.(err.message, "error");
        } finally {
            setRunning(false);
        }
    };

    const handleFilterChange = (code, value) => {
        setFilters(prev => ({ ...prev, [code]: value }));
    };

    if (loading) return (
        <div className="flex flex-col items-center justify-center p-20 text-gold/30 animate-pulse font-mono text-[10px] uppercase tracking-[0.3em] gap-4">
            <Loader2 className="animate-spin w-8 h-8" />
            Querying Matrix Ledger...
        </div>
    );

    if (error) return (
        <div className="p-8 text-red-400 bg-red-900/10 border border-red-500/20 rounded-xl font-mono text-xs uppercase tracking-wider">
            Critical Failure: {error}
        </div>
    );

    const canExport = metadata?.report?.is_exportable;

    return (
        <div className="space-y-12 animate-slide-up">
            <div className="flex flex-col md:flex-row justify-between items-start gap-6">
                <div className="relative">
                    <div className="absolute -left-8 top-0 bottom-0 w-px bg-gradient-to-b from-gold/30 to-transparent"></div>
                    <h2 className="text-4xl font-serif font-black text-white tracking-tight">{metadata.report.label}</h2>
                    <p className="text-slate-400 font-light mt-2 italic tracking-wide">{metadata.report.description}</p>
                </div>
                <div className="flex gap-4">
                    {canExport && (
                        <button
                            onClick={() => runReport(true)}
                            className="btn-outline py-3 text-[10px] tracking-[0.2em]"
                        >
                            <Download size={14} /> EXPORT_DATA
                        </button>
                    )}
                    <button
                        disabled={running}
                        onClick={() => runReport()}
                        className="btn-primary py-3 text-[10px] tracking-[0.2em]"
                    >
                        {running ? <Loader2 size={14} className="animate-spin" /> : <RefreshCw size={14} />}
                        SYNC_ENGINE
                    </button>
                </div>
            </div>

            {/* Filters Section */}
            {metadata.filters.length > 0 && (
                <div className="premium-card p-8 md:p-10 bg-navy-lighter/20 backdrop-blur-sm">
                    <div className="flex items-center gap-3 mb-8">
                        <Filter size={14} className="text-gold" />
                        <span className="text-[10px] font-mono font-bold uppercase tracking-[0.3em] text-gold/40">Query Parameters</span>
                    </div>
                    <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-8">
                        {metadata.filters.map(f => (
                            <div key={f.filter_id} className="space-y-3">
                                <label className="text-[9px] font-mono font-bold text-slate-500 uppercase tracking-widest">
                                    {f.display_label}
                                </label>
                                <input
                                    type="text"
                                    className="input-standard py-3 text-xs font-mono"
                                    value={filters[f.attribute_code] || ""}
                                    onChange={(e) => handleFilterChange(f.attribute_code, e.target.value)}
                                    placeholder={`Filter ${f.display_label.toLowerCase()}...`}
                                />
                            </div>
                        ))}
                    </div>
                </div>
            )}

            {/* Results Table */}
            {results ? (
                <div className="premium-card overflow-hidden bg-navy-lighter/10">
                    <div className="overflow-x-auto custom-scrollbar">
                        <table className="w-full text-left border-collapse">
                            <thead>
                                <tr className="bg-navy-deep/80 border-b border-gold/10">
                                    {results.columns.map(col => (
                                        <th key={col} className="px-10 py-6 text-[10px] font-mono font-bold text-gold uppercase tracking-[0.3em] whitespace-nowrap">
                                            {col.replace(/_/g, ' ')}
                                        </th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gold/5">
                                {results.rows.length > 0 ? (
                                    results.rows.map((row, idx) => (
                                        <tr key={idx} className="hover:bg-gold/5 transition-all duration-300 group">
                                            {results.columns.map(col => (
                                                <td key={col} className="px-10 py-6 text-sm font-light text-cream group-hover:text-white transition-colors">
                                                    {row[col]?.toString() || '-'}
                                                </td>
                                            ))}
                                        </tr>
                                    ))
                                ) : (
                                    <tr>
                                        <td colSpan={results.columns.length} className="px-10 py-32 text-center">
                                            <div className="flex flex-col items-center gap-4">
                                                <div className="w-20 h-20 bg-navy-deep rounded-full border border-gold/10 flex items-center justify-center text-gold/20 shadow-inner">
                                                    <AlertCircle size={40} />
                                                </div>
                                                <p className="text-gold/40 font-mono font-bold uppercase tracking-[0.2em] text-xs">No matching nodes located</p>
                                            </div>
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    </div>
                    <div className="px-10 py-5 bg-navy-deep border-t border-gold/10 flex justify-between items-center text-[9px] font-mono font-bold text-gold/40 uppercase tracking-[0.3em]">
                        <div className="flex gap-10">
                            <span className="flex items-center gap-2">
                                <span className="w-1 h-1 bg-gold rounded-full"></span>
                                NODES: {results.row_count}
                            </span>
                            <span className="flex items-center gap-2">
                                <span className="w-1 h-1 bg-teal-bright rounded-full"></span>
                                STATUS: SECURE_HASH
                            </span>
                        </div>
                        <span className="opacity-50">TRACE_ID: {results.execution_id.split('-')[0]}</span>
                    </div>
                </div>
            ) : (
                !running && (
                    <div className="py-40 premium-card flex flex-col items-center justify-center bg-navy-lighter/10 border-dashed border border-gold/10">
                        <div className="w-24 h-24 bg-navy-deep border border-gold/5 rounded-3xl flex items-center justify-center text-gold/10 mb-8 shadow-gold-hover transition-all">
                            <Table size={48} />
                        </div>
                        <h3 className="text-2xl font-serif font-bold text-white mb-3 tracking-tight">Intelligence Canvas</h3>
                        <p className="text-slate-400 font-light max-w-sm text-center text-sm leading-relaxed tracking-wide italic">
                            Configure your query parameters above and synchronize the subsystem to generate actionable data insights.
                        </p>
                    </div>
                )
            )}
        </div>
    );
};

export default ReportViewer;
