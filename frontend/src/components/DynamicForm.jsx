import React, { useState, useEffect } from 'react';
import { apiFetch } from '../api/client';
import { AlertCircle, CheckCircle2, Loader2, Save } from 'lucide-react';

/**
 * DynamicForm.jsx
 * 
 * Renders a form based on metadata from form_master/sections/fields.
 * LAW 2: No custom columns — all values go to EAV.
 */
const DynamicForm = ({ formCode, onNotify }) => {
    const [metadata, setMetadata] = useState(null);
    const [formData, setFormData] = useState({});
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [submitting, setSubmitting] = useState(false);

    useEffect(() => {
        async function fetchMetadata() {
            try {
                const data = await apiFetch(`/forms/${formCode}`);
                setMetadata(data);

                // Initialise form data with defaults
                const initial = {};
                data.structure.forEach(sec => {
                    sec.fields.forEach(field => {
                        initial[field.attribute_code] = field.default_value || "";
                    });
                });
                setFormData(initial);
            } catch (err) {
                setError(err.message);
            } finally {
                setLoading(false);
            }
        }
        fetchMetadata();
    }, [formCode]);

    const handleChange = (e, code) => {
        const { value, type, checked } = e.target;
        setFormData(prev => ({
            ...prev,
            [code]: type === 'checkbox' ? checked : value
        }));
    };

    const checkVisibility = (rule) => {
        if (!rule) return true;
        try {
            // Very basic JSON logic evaluator for visibility
            // Expects: { "var": "attr_code" } or comparison
            if (rule.var) return !!formData[rule.var];
            if (rule.eq) return formData[rule.eq[0]] === rule.eq[1];
            return true;
        } catch {
            return true;
        }
    };

    const validate = () => {
        // Basic client-side validation
        for (const section of metadata.structure) {
            for (const field of section.fields) {
                if (!checkVisibility(field.visibility_rule)) continue;

                const val = formData[field.attribute_code];
                if (field.is_required && !val) {
                    onNotify?.(`Field "${field.label_override || field.attribute_code}" is required`, 'error');
                    return false;
                }
            }
        }
        return true;
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        if (!validate()) return;

        setSubmitting(true);
        try {
            // LAW 2: Transform flat formData into the array shape expected by
            // EntityCreateRequest: [{ attribute_code, value }, ...]
            // This keeps the frontend free of schema concerns (attribute_code is
            // already the key used throughout the EAV form rendering).
            const attributesPayload = Object.entries(formData).map(([attribute_code, value]) => ({
                attribute_code,
                value,
            }));
            const res = await apiFetch(`/entities/${metadata.form.entity_code}/records`, {
                method: "POST",
                body: JSON.stringify({ attributes: attributesPayload })
            });
            onNotify?.("Record created successfully", "success");
            onNotify?.(`Record ID: ${res.record_id}`, "info");
        } catch (err) {
            onNotify?.(err.message, "error");
        } finally {
            setSubmitting(false);
        }
    };

    if (loading) return (
        <div className="flex flex-col items-center justify-center p-20 text-gold/30 animate-pulse font-mono text-[10px] uppercase tracking-[0.3em] gap-4">
            <Loader2 className="animate-spin w-8 h-8" />
            Initializing Neural Interface...
        </div>
    );

    if (error) return (
        <div className="p-8 text-red-400 bg-red-900/10 border border-red-500/20 rounded-xl font-mono text-xs uppercase tracking-wider">
            Critical Failure: {error}
        </div>
    );

    return (
        <form onSubmit={handleSubmit} className="space-y-16 pb-32 animate-slide-up">
            {/* Header Section */}
            <div className="flex flex-col gap-4 relative">
                <div className="absolute -left-8 top-0 bottom-0 w-px bg-gradient-to-b from-gold/30 to-transparent"></div>
                <h2 className="text-4xl font-serif font-black text-white tracking-tight">{metadata.form.display_name}</h2>
                {metadata.form.description && (
                    <p className="text-slate-400 font-light leading-relaxed max-w-3xl italic tracking-wide">{metadata.form.description}</p>
                )}
            </div>

            {/* Dynamic Sections */}
            {metadata.structure.map((section) => (
                <div key={section.section.section_id} className="premium-card p-10 md:p-14 bg-navy-lighter/30 backdrop-blur-sm">
                    <div className="flex items-center gap-5 mb-10 border-b border-gold/5 pb-8 relative">
                        <div className="w-1.5 h-6 bg-gold rounded-full shadow-gold active-glow absolute -left-[56px] md:-left-[72px]"></div>
                        <h3 className="text-xs font-mono font-bold text-gold uppercase tracking-[0.3em]">
                            {section.section.display_label}
                        </h3>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-2 gap-x-12 gap-y-10">
                        {section.fields.map((field) => (
                            checkVisibility(field.visibility_rule) && (
                                <div key={field.field_id} className={`flex flex-col gap-3 ${field.widget_type === 'textarea' ? 'md:col-span-2' : ''}`}>
                                    <div className="flex items-center justify-between">
                                        <label className="text-[10px] font-mono font-bold text-slate-500 uppercase tracking-[0.15em] flex items-center gap-2">
                                            {field.label_override || field.display_label}
                                            {field.is_required && <span className="text-gold animate-pulse text-lg leading-none mt-1">*</span>}
                                        </label>
                                        {field.help_text && (
                                            <div className="group relative">
                                                <AlertCircle size={14} className="text-gold/20 cursor-help hover:text-gold transition-colors" />
                                                <div className="absolute bottom-full right-0 mb-3 w-56 p-4 bg-navy-deep text-white text-[10px] rounded-xl border border-gold/20 opacity-0 group-hover:opacity-100 transition-all pointer-events-none z-20 font-light leading-relaxed backdrop-blur-xl shadow-gold translate-y-2 group-hover:translate-y-0">
                                                    {field.help_text}
                                                </div>
                                            </div>
                                        )}
                                    </div>

                                    {field.widget_type === 'text_input' && (
                                        <input
                                            type="text"
                                            className="input-standard"
                                            value={formData[field.attribute_code] || ""}
                                            onChange={(e) => handleChange(e, field.attribute_code)}
                                            placeholder={field.placeholder || "Null_String..."}
                                        />
                                    )}

                                    {field.widget_type === 'number_input' && (
                                        <input
                                            type="number"
                                            className="input-standard font-mono"
                                            value={formData[field.attribute_code] || ""}
                                            onChange={(e) => handleChange(e, field.attribute_code)}
                                            placeholder="0x00"
                                        />
                                    )}

                                    {field.widget_type === 'date_picker' && (
                                        <input
                                            type="date"
                                            className="input-standard font-mono"
                                            value={formData[field.attribute_code] || ""}
                                            onChange={(e) => handleChange(e, field.attribute_code)}
                                        />
                                    )}

                                    {field.widget_type === 'textarea' && (
                                        <textarea
                                            className="input-standard min-h-[160px] resize-none py-5 leading-relaxed font-light"
                                            value={formData[field.attribute_code] || ""}
                                            onChange={(e) => handleChange(e, field.attribute_code)}
                                            placeholder="Awaiting comprehensive data input..."
                                        />
                                    )}

                                    {field.widget_type === 'checkbox' && (
                                        <label className="flex items-center gap-4 p-5 bg-navy-deep border border-gold/10 rounded-xl cursor-none hover:bg-gold/5 hover:border-gold/30 transition-all group">
                                            <div className="relative flex items-center">
                                                <input
                                                    type="checkbox"
                                                    className="peer w-6 h-6 opacity-0 absolute cursor-none"
                                                    checked={formData[field.attribute_code] || false}
                                                    onChange={(e) => handleChange(e, field.attribute_code)}
                                                />
                                                <div className="w-6 h-6 bg-navy border-2 border-gold/20 rounded-lg peer-checked:bg-gold peer-checked:border-gold transition-all flex items-center justify-center shadow-inner">
                                                    <CheckCircle2 size={14} className="text-navy opacity-0 peer-checked:opacity-100 transition-all scale-50 peer-checked:scale-100" />
                                                </div>
                                            </div>
                                            <span className="text-xs font-mono font-bold text-slate-500 group-hover:text-gold transition-colors uppercase tracking-widest">Acknowledge & Sync</span>
                                        </label>
                                    )}
                                </div>
                            )
                        ))}
                    </div>
                </div>
            ))}

            <div className="fixed bottom-12 left-1/2 -translate-x-1/2 md:translate-x-0 md:static flex justify-end z-[45]">
                <button
                    type="submit"
                    disabled={submitting}
                    className="btn-primary min-w-[280px] h-16 justify-center text-xs font-mono font-black uppercase tracking-[0.2em] shadow-gold-hover scale-110 md:scale-100"
                >
                    {submitting ? (
                        <>
                            <Loader2 className="w-5 h-5 animate-spin" />
                            Transmitting...
                        </>
                    ) : (
                        <>
                            <Save className="w-5 h-5" />
                            Synchronize Subsystem
                        </>
                    )}
                </button>
            </div>
        </form>
    );
};

export default DynamicForm;
