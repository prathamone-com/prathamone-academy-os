import React, { useState, useEffect } from 'react';
import { apiFetch } from '../api/client';
import { PlayCircle, Loader2, AlertTriangle, CheckCircle } from 'lucide-react';

/**
 * WorkflowActions.jsx
 * 
 * Fetches available transitions for a record and renders action buttons.
 * LAW 3: No if(status == ...) — driven by workflow_transitions.
 */
const WorkflowActions = ({ entityCode, recordId, onNotify, onTransitionSuccess }) => {
    const [actions, setActions] = useState([]);
    const [loading, setLoading] = useState(true);
    const [submitting, setSubmitting] = useState(null); // stores the action code being submitted

    const fetchActions = async () => {
        try {
            const data = await apiFetch(`/workflow/available-transitions/${entityCode}/${recordId}`);
            setActions(data);
        } catch (err) {
            console.error("Failed to fetch workflow actions:", err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        if (recordId) fetchActions();
    }, [entityCode, recordId]);

    const handleAction = async (action) => {
        setSubmitting(action.action);
        try {
            const res = await apiFetch('/workflow/transition', {
                method: 'POST',
                body: JSON.stringify({
                    entity_record_id: recordId,
                    entity_code: entityCode,
                    target_state_code: action.to_state,
                    context: {} // Potential for comments/reasoning
                })
            });

            if (res.allowed) {
                onNotify?.(`Applied action: ${action.label}`, "success");
                onTransitionSuccess?.(res);
                await fetchActions(); // Refresh available actions
            } else {
                onNotify?.(`Action blocked: ${res.reason}`, "error");
            }
        } catch (err) {
            onNotify?.(err.message, "error");
        } finally {
            setSubmitting(null);
        }
    };

    if (loading) return <Loader2 className="animate-spin text-slate-400 w-5 h-5" />;
    if (actions.length === 0) return null;

    return (
        <div className="flex flex-wrap items-center gap-3 animate-slide-up bg-white/50 backdrop-blur-sm p-2 rounded-2xl border border-slate-100">
            <div className="px-4 py-2 border-r border-slate-200 mr-1 flex items-center gap-2">
                <div className="w-2 h-2 bg-brand-500 rounded-full animate-pulse"></div>
                <span className="text-[10px] font-black text-slate-400 uppercase tracking-[0.2em]">Next Actions</span>
            </div>
            {actions.map((action) => (
                <button
                    key={action.action}
                    disabled={!!submitting}
                    onClick={() => handleAction(action)}
                    className={`
                        group flex items-center gap-2 px-5 py-2.5 rounded-xl text-xs font-bold transition-all duration-300 shadow-sm
                        ${action.action.includes('reject') || action.action.includes('block')
                            ? 'bg-red-50 text-red-600 hover:bg-red-500 hover:text-white hover:shadow-red-500/20'
                            : 'bg-white border border-slate-200 text-slate-700 hover:bg-brand-600 hover:text-white hover:border-brand-600 hover:shadow-brand-500/20'}
                        disabled:opacity-50 disabled:cursor-not-allowed transform active:scale-95
                    `}
                >
                    {submitting === action.action ? (
                        <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                        <PlayCircle className={`w-4 h-4 transition-transform duration-300 ${submitting ? '' : 'group-hover:translate-x-0.5'}`} />
                    )}
                    {action.label.toUpperCase()}
                </button>
            ))}
        </div>
    );
};

export default WorkflowActions;
