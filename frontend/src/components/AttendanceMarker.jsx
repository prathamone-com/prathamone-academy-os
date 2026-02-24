import { useState, useEffect } from 'react';
import { apiFetch } from '../api/client';
import { Check, X, Clock, HelpCircle, Save, Calendar, ChevronRight, User, Loader2 } from 'lucide-react';

const AttendanceMarker = () => {
    const [students, setStudents] = useState([]);
    const [attendance, setAttendance] = useState({}); // { student_id: status }
    const [date, setDate] = useState(new Date().toISOString().split('T')[0]);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [success, setSuccess] = useState(false);

    useEffect(() => {
        fetchStudents();
    }, []);

    const fetchStudents = async () => {
        try {
            setLoading(true);
            const data = await apiFetch('/entities/STUDENT/records');
            const studentList = data.map(record => {
                const attrs = {};
                record.attributes.forEach(a => attrs[a.attribute_code] = a.value);
                return {
                    id: record.record_id,
                    name: attrs.full_name || 'Unknown Student',
                    class: attrs.class_enrolled || 'N/A',
                    admission_no: attrs.admission_number || 'N/A'
                };
            });
            setStudents(studentList);

            // Default everyone to PRESENT
            const initial = {};
            studentList.forEach(s => initial[s.id] = 'PRESENT');
            setAttendance(initial);

            setLoading(false);
        } catch (err) {
            console.error('Failed to fetch students', err);
            setLoading(false);
        }
    };

    const handleStatusChange = (studentId, status) => {
        setAttendance(prev => ({ ...prev, [studentId]: status }));
    };

    const handleMarkAll = (status) => {
        const updated = {};
        students.forEach(s => updated[s.id] = status);
        setAttendance(updated);
    };

    const handleSubmit = async () => {
        try {
            setSaving(true);
            const entries = Object.entries(attendance).map(([studentId, status]) => ({
                student_id: studentId,
                status: status
            }));

            await apiFetch('/attendance/bulk', {
                method: 'POST',
                body: JSON.stringify({
                    attendance_date: date,
                    entries: entries
                })
            });

            setSuccess(true);
            setSaving(false);
            setTimeout(() => setSuccess(false), 3000);
        } catch (err) {
            console.error('Failed to save attendance', err);
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <div className="flex flex-col items-center justify-center p-20 text-gold/40">
                <Loader2 size={48} className="animate-spin mb-4" />
                <p className="font-mono text-xs uppercase tracking-[0.3em]">Synching Student Registry...</p>
            </div>
        );
    }

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-700">
            {/* Header */}
            <header className="flex flex-col md:flex-row md:items-end justify-between gap-6">
                <div>
                    <nav className="flex items-center gap-2 text-[10px] font-mono font-medium text-teal-bright uppercase tracking-[0.2em] mb-4">
                        <span>Academic</span>
                        <ChevronRight size={10} />
                        <span>Attendance Ledger</span>
                    </nav>
                    <h1 className="text-4xl font-serif font-black text-white tracking-tight">Daily Roll Call</h1>
                </div>

                <div className="flex items-center gap-4">
                    <div className="relative group">
                        <Calendar size={14} className="absolute left-4 top-1/2 -translate-y-1/2 text-gold/40" />
                        <input
                            type="date"
                            value={date}
                            onChange={(e) => setDate(e.target.value)}
                            className="input-standard pl-10 pr-4 py-2 bg-navy-lighter/30 border-gold/10 text-xs font-mono uppercase tracking-wider"
                        />
                    </div>
                </div>
            </header>

            {/* Controls */}
            <div className="flex flex-wrap items-center justify-between gap-4 p-4 bg-navy-lighter/20 border border-gold/5 rounded-2xl">
                <div className="flex items-center gap-2">
                    <button
                        onClick={() => handleMarkAll('PRESENT')}
                        className="px-4 py-1.5 rounded-full border border-teal-bright/20 bg-teal-bright/5 text-teal-bright text-[10px] uppercase font-bold tracking-widest hover:bg-teal-bright/10 transition-colors"
                    >
                        Mark All Present
                    </button>
                    <button
                        onClick={() => handleMarkAll('ABSENT')}
                        className="px-4 py-1.5 rounded-full border border-rose-500/20 bg-rose-500/5 text-rose-500 text-[10px] uppercase font-bold tracking-widest hover:bg-rose-500/10 transition-colors"
                    >
                        Mark All Absent
                    </button>
                </div>

                <button
                    onClick={handleSubmit}
                    disabled={saving}
                    className="flex items-center gap-2 px-8 py-3 bg-gold text-navy-deep rounded-xl font-bold uppercase tracking-widest text-xs hover:scale-105 active:scale-95 transition-all shadow-xl shadow-gold/10 disabled:opacity-50"
                >
                    {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
                    {success ? 'Ledger Synced' : 'Commit to Registry'}
                </button>
            </div>

            {/* Grid */}
            <div className="premium-card overflow-hidden">
                <table className="w-full text-left font-mono text-xs">
                    <thead>
                        <tr className="bg-navy-lighter/30 border-b border-gold/10">
                            <th className="p-4 text-gold/60 uppercase tracking-widest font-black">Student</th>
                            <th className="p-4 text-gold/60 uppercase tracking-widest font-black">Ref No</th>
                            <th className="p-4 text-gold/60 uppercase tracking-widest font-black">Class</th>
                            <th className="p-4 text-gold/60 uppercase tracking-widest font-black text-center">Status</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-gold/5">
                        {students.map(s => (
                            <tr key={s.id} className="hover:bg-gold/5 transition-colors group">
                                <td className="p-4">
                                    <div className="flex items-center gap-3">
                                        <div className="w-8 h-8 rounded-lg bg-navy-lighter flex items-center justify-center text-gold/40 border border-gold/5">
                                            <User size={14} />
                                        </div>
                                        <span className="font-serif text-sm font-bold text-white group-hover:text-gold transition-colors">{s.name}</span>
                                    </div>
                                </td>
                                <td className="p-4 text-slate-400">{s.admission_no}</td>
                                <td className="p-4">
                                    <span className="px-2 py-0.5 rounded bg-gold/5 border border-gold/10 text-[10px] text-gold/60">
                                        {s.class}
                                    </span>
                                </td>
                                <td className="p-4">
                                    <div className="flex items-center justify-center gap-2">
                                        <StatusButton
                                            active={attendance[s.id] === 'PRESENT'}
                                            icon={Check}
                                            color="text-teal-bright"
                                            bgColor="bg-teal-bright/10"
                                            borderColor="border-teal-bright/20"
                                            label="P"
                                            onClick={() => handleStatusChange(s.id, 'PRESENT')}
                                        />
                                        <StatusButton
                                            active={attendance[s.id] === 'ABSENT'}
                                            icon={X}
                                            color="text-rose-500"
                                            bgColor="bg-rose-500/10"
                                            borderColor="border-rose-500/20"
                                            label="A"
                                            onClick={() => handleStatusChange(s.id, 'ABSENT')}
                                        />
                                        <StatusButton
                                            active={attendance[s.id] === 'LATE'}
                                            icon={Clock}
                                            color="text-amber-400"
                                            bgColor="bg-amber-400/10"
                                            borderColor="border-amber-400/20"
                                            label="L"
                                            onClick={() => handleStatusChange(s.id, 'LATE')}
                                        />
                                        <StatusButton
                                            active={attendance[s.id] === 'EXCUSED'}
                                            icon={HelpCircle}
                                            color="text-blue-400"
                                            bgColor="bg-blue-400/10"
                                            borderColor="border-blue-400/20"
                                            label="E"
                                            onClick={() => handleStatusChange(s.id, 'EXCUSED')}
                                        />
                                    </div>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>
    );
};

const StatusButton = ({ active, icon: Icon, color, bgColor, borderColor, label, onClick }) => (
    <button
        onClick={onClick}
        title={label}
        className={`w-10 h-10 rounded-xl border flex items-center justify-center transition-all ${active ? `${color} ${bgColor} ${borderColor} scale-110 shadow-lg shadow-${color}/5` : 'border-gold/5 text-gold/20 hover:border-gold/20'}`}
    >
        <Icon size={16} strokeWidth={3} />
    </button>
);

export default AttendanceMarker;
