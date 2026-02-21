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
            const entityCode = metadata.form.entity_id; // Mapping form to entity
            // Note: In real app, we fetch entity_code from entity_master
            const res = await apiFetch(`/entities/${metadata.form.entity_code}/records`, {
                method: "POST",
                body: JSON.stringify({ attributes: formData })
            });
            onNotify?.("Record created successfully", "success");
            onNotify?.(`Record ID: ${res.record_id}`, "info");
        } catch (err) {
            onNotify?.(err.message, "error");
        } finally {
            setSubmitting(false);
        }
    };

    if (loading) return <div className="flex items-center gap-2 p-8"><Loader2 className="animate-spin" /> Loading form...</div>;
    if (error) return <div className="p-4 text-red-600 bg-red-50 border border-red-200 rounded-lg">{error}</div>;

    return (
        <form onSubmit={handleSubmit} className="space-y-10 pb-20">
            {/* Header Section */}
            <div className="flex flex-col gap-2">
                <h2 className="text-3xl font-black text-slate-900 tracking-tight">{metadata.form.display_name}</h2>
                {metadata.form.description && (
                    <p className="text-slate-500 font-medium leading-relaxed max-w-2xl">{metadata.form.description}</p>
                )}
            </div>

            {/* Dynamic Sections */}
            {metadata.structure.map((section) => (
                <div key={section.section.section_id} className="premium-card p-8 md:p-10">
                    <div className="flex items-center gap-3 mb-8 border-b border-slate-50 pb-6">
                        <div className="w-1.5 h-6 bg-brand-500 rounded-full shadow-lg shadow-brand-500/20"></div>
                        <h3 className="text-lg font-bold text-slate-800 tracking-tight uppercase tracking-widest text-xs">
                            {section.section.display_label}
                        </h3>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-6">
                        {section.fields.map((field) => (
                            checkVisibility(field.visibility_rule) && (
                                <div key={field.field_id} className={`flex flex-col gap-2 ${field.widget_type === 'textarea' ? 'md:col-span-2' : ''}`}>
                                    <div className="flex items-center justify-between">
                                        <label className="text-xs font-black text-slate-500 uppercase tracking-wider flex items-center gap-1">
                                            {field.label_override || field.display_label}
                                            {field.is_required && <span className="text-brand-500">*</span>}
                                        </label>
                                        {field.help_text && (
                                            <div className="group relative">
                                                <AlertCircle size={14} className="text-slate-300 cursor-help hover:text-brand-500 transition-colors" />
                                                <div className="absolute bottom-full right-0 mb-2 w-48 p-2 bg-slate-900 text-white text-[10px] rounded-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none z-10 font-medium">
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
                                            placeholder={field.placeholder || "Enter text..."}
                                        />
                                    )}

                                    {field.widget_type === 'number_input' && (
                                        <input
                                            type="number"
                                            className="input-standard"
                                            value={formData[field.attribute_code] || ""}
                                            onChange={(e) => handleChange(e, field.attribute_code)}
                                            placeholder="0"
                                        />
                                    )}

                                    {field.widget_type === 'date_picker' && (
                                        <input
                                            type="date"
                                            className="input-standard"
                                            value={formData[field.attribute_code] || ""}
                                            onChange={(e) => handleChange(e, field.attribute_code)}
                                        />
                                    )}

                                    {field.widget_type === 'textarea' && (
                                        <textarea
                                            className="input-standard min-h-[140px] resize-none py-4"
                                            value={formData[field.attribute_code] || ""}
                                            onChange={(e) => handleChange(e, field.attribute_code)}
                                            placeholder="Provide detailed description..."
                                        />
                                    )}

                                    {field.widget_type === 'checkbox' && (
                                        <label className="flex items-center gap-3 p-4 bg-slate-50 border border-slate-100 rounded-xl cursor-pointer hover:bg-white hover:border-brand-500/20 transition-all group">
                                            <div className="relative flex items-center">
                                                <input
                                                    type="checkbox"
                                                    className="peer w-5 h-5 opacity-0 absolute cursor-pointer"
                                                    checked={formData[field.attribute_code] || false}
                                                    onChange={(e) => handleChange(e, field.attribute_code)}
                                                />
                                                <div className="w-5 h-5 bg-white border-2 border-slate-200 rounded-lg peer-checked:bg-brand-600 peer-checked:border-brand-600 transition-all flex items-center justify-center">
                                                    <CheckCircle2 size={12} className="text-white opacity-0 peer-checked:opacity-100 transition-opacity" />
                                                </div>
                                            </div>
                                            <span className="text-sm font-bold text-slate-600 group-hover:text-slate-900 transition-colors">Yes, confirmed</span>
                                        </label>
                                    )}
                                </div>
                            )
                        ))}
                    </div>
                </div>
            ))}

            <div className="fixed bottom-10 left-1/2 -translate-x-1/2 md:translate-x-0 md:static flex justify-end">
                <button
                    type="submit"
                    disabled={submitting}
                    className="btn-primary min-w-[200px] justify-center px-10 py-4 text-sm shadow-2xl shadow-brand-500/40"
                >
                    {submitting ? (
                        <>
                            <Loader2 className="w-5 h-5 animate-spin" />
                            Processing...
                        </>
                    ) : (
                        <>
                            <Save className="w-5 h-5" />
                            Finalize & Save Record
                        </>
                    )}
                </button>
            </div>
        </form>
    );
};

export default DynamicForm;
