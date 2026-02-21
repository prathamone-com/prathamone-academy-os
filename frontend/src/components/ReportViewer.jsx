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

    if (loading) return <div className="flex items-center gap-2 p-8"><Loader2 className="animate-spin" /> Fetching report schema...</div>;
    if (error) return <div className="p-4 text-red-600 bg-red-50 border border-red-200 rounded-lg">{error}</div>;

    const canExport = metadata?.report?.is_exportable; // In real app, check role access too

    return (
        <div className="space-y-8 animate-slide-up">
            <div className="flex flex-col md:flex-row justify-between items-start gap-4">
                <div>
                    <h2 className="text-3xl font-black text-slate-900 tracking-tight">{metadata.report.label}</h2>
                    <p className="text-slate-500 font-medium mt-1">{metadata.report.description}</p>
                </div>
                <div className="flex gap-3">
                    {canExport && (
                        <button
                            onClick={() => runReport(true)}
                            className="flex items-center gap-2 px-5 py-2.5 text-xs font-bold text-slate-600 bg-white border border-slate-200 rounded-xl hover:bg-slate-50 hover:border-slate-300 transition-all shadow-sm active:scale-95"
                        >
                            <Download size={16} /> EXPORT CSV
                        </button>
                    )}
                    <button
                        disabled={running}
                        onClick={() => runReport()}
                        className="btn-primary py-2.5 text-xs tracking-widest"
                    >
                        {running ? <Loader2 size={16} className="animate-spin" /> : <RefreshCw size={16} />}
                        REFRESH DATA
                    </button>
                </div>
            </div>

            {/* Filters Section */}
            {metadata.filters.length > 0 && (
                <div className="premium-card p-6 md:p-8 bg-slate-50/50">
                    <div className="flex items-center gap-2 mb-6">
                        <Filter size={14} className="text-brand-500" />
                        <span className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-400">Query Parameters</span>
                    </div>
                    <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-6">
                        {metadata.filters.map(f => (
                            <div key={f.filter_id} className="space-y-2">
                                <label className="text-[10px] font-black text-slate-500 uppercase tracking-wider">
                                    {f.display_label}
                                </label>
                                <input
                                    type="text"
                                    className="input-standard py-2.5 text-xs"
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
                <div className="premium-card overflow-hidden">
                    <div className="overflow-x-auto custom-scrollbar">
                        <table className="w-full text-left border-collapse">
                            <thead>
                                <tr className="bg-slate-900 border-b border-slate-800">
                                    {results.columns.map(col => (
                                        <th key={col} className="px-8 py-5 text-[10px] font-black text-slate-400 uppercase tracking-[0.2em] whitespace-nowrap">
                                            {col.replace(/_/g, ' ')}
                                        </th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100">
                                {results.rows.length > 0 ? (
                                    results.rows.map((row, idx) => (
                                        <tr key={idx} className="hover:bg-slate-50/80 transition-colors group">
                                            {results.columns.map(col => (
                                                <td key={col} className="px-8 py-5 text-sm font-semibold text-slate-600 group-hover:text-slate-900">
                                                    {row[col]?.toString() || '-'}
                                                </td>
                                            ))}
                                        </tr>
                                    ))
                                ) : (
                                    <tr>
                                        <td colSpan={results.columns.length} className="px-8 py-20 text-center">
                                            <div className="flex flex-col items-center gap-3">
                                                <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center text-slate-200">
                                                    <AlertCircle size={32} />
                                                </div>
                                                <p className="text-slate-400 font-bold uppercase tracking-widest text-xs">No matching records found</p>
                                            </div>
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    </div>
                    <div className="px-8 py-4 bg-slate-50 border-t border-slate-100 flex justify-between items-center text-[10px] font-black text-slate-400 uppercase tracking-widest">
                        <div className="flex gap-6">
                            <span>RECORDS: {results.row_count}</span>
                            <span>STATUS: LIVE_OPTIMIZED</span>
                        </div>
                        <span className="opacity-50">TXID: {results.execution_id.split('-')[0]}</span>
                    </div>
                </div>
            ) : (
                !running && (
                    <div className="py-32 premium-card flex flex-col items-center justify-center bg-white/50 border-dashed border-2 border-slate-200">
                        <div className="w-20 h-20 bg-slate-100 rounded-3xl flex items-center justify-center text-slate-300 mb-6 shadow-inner">
                            <Table size={40} />
                        </div>
                        <h3 className="text-lg font-bold text-slate-900 mb-2 tracking-tight">Report Canvas Ready</h3>
                        <p className="text-slate-400 font-medium max-w-xs text-center text-sm leading-relaxed">
                            Configure your query filters above and click "Run Report" to generate data insights.
                        </p>
                    </div>
                )
            )}
        </div>
    );
};

export default ReportViewer;
