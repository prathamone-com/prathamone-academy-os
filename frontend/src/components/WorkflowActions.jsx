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

    if (loading) return <Loader2 className="animate-spin text-gold/30 w-5 h-5" />;
    if (actions.length === 0) return null;

    return (
        <div className="flex flex-wrap items-center gap-4 animate-slide-up bg-navy-lighter/40 backdrop-blur-xl p-2.5 rounded-xl border border-gold/10 shadow-gold">
            <div className="px-5 py-2 border-r border-gold/10 mr-1 flex items-center gap-3">
                <div className="w-1.5 h-1.5 bg-teal-bright rounded-full animate-pulse shadow-[0_0_8px_rgba(34,211,238,0.6)]"></div>
                <span className="text-[9px] font-mono font-bold text-gold/40 uppercase tracking-[0.3em]">Neural Transitions</span>
            </div>
            {actions.map((action) => (
                <button
                    key={action.action}
                    disabled={!!submitting}
                    onClick={() => handleAction(action)}
                    className={`
                        group flex items-center gap-3 px-6 py-2.5 rounded-lg text-[10px] font-mono font-bold uppercase tracking-widest transition-all duration-500 relative overflow-hidden
                        ${action.action.includes('reject') || action.action.includes('block')
                            ? 'bg-navy-deep border border-red-500/30 text-red-400 hover:bg-red-500 hover:text-white'
                            : 'bg-navy-deep border border-gold/20 text-gold-soft hover:bg-gold hover:text-navy hover:shadow-gold'}
                        disabled:opacity-40 disabled:scale-95 transform active:scale-90 cursor-none
                    `}
                >
                    {submitting === action.action ? (
                        <Loader2 className="w-3.5 h-3.5 animate-spin" />
                    ) : (
                        <PlayCircle className={`w-3.5 h-3.5 transition-all duration-500 ${submitting ? '' : 'group-hover:translate-x-1 group-hover:scale-110'}`} />
                    )}
                    {action.label}
                </button>
            ))}
        </div>
    );
};

export default WorkflowActions;
