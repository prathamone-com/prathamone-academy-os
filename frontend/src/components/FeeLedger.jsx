import { useState, useEffect, useCallback } from 'react';
import {
  CreditCard, Search, AlertCircle, CheckCircle2, Clock,
  ArrowUpRight, ArrowDownLeft, Ban, RefreshCw, ChevronDown,
  ChevronUp, Receipt, IndianRupee, TrendingDown, BadgePercent,
  Loader2, Plus, X
} from 'lucide-react';
import { apiFetch } from '../api/client';

// =============================================================================
// helpers
// =============================================================================

const fmt = (n) => new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(n ?? 0);
const fmtDate = (s) => s ? new Date(s).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';

const STATE_META = {
  DEMAND_RAISED: { label: 'Demand Raised', color: 'text-indigo-400  border-indigo-400/30  bg-indigo-400/10', icon: Clock },
  PARTIALLY_PAID: { label: 'Partially Paid', color: 'text-amber-400   border-amber-400/30   bg-amber-400/10', icon: ArrowUpRight },
  PAID: { label: 'Paid in Full', color: 'text-emerald-400 border-emerald-400/30 bg-emerald-400/10', icon: CheckCircle2 },
  OVERDUE: { label: 'Overdue', color: 'text-red-400     border-red-400/30     bg-red-400/10', icon: AlertCircle },
  WAIVED: { label: 'Waived', color: 'text-purple-400  border-purple-400/30  bg-purple-400/10', icon: BadgePercent },
  REFUND_INITIATED: { label: 'Refund Initiated', color: 'text-sky-400     border-sky-400/30     bg-sky-400/10', icon: ArrowDownLeft },
  REFUNDED: { label: 'Refunded', color: 'text-cyan-400    border-cyan-400/30    bg-cyan-400/10', icon: ArrowDownLeft },
};

const ENTRY_META = {
  PAYMENT: { label: 'Payment', color: 'text-emerald-400', sign: '+', icon: ArrowUpRight },
  REFUND: { label: 'Refund', color: 'text-sky-400', sign: '−', icon: ArrowDownLeft },
  ADJUSTMENT: { label: 'Adjustment', color: 'text-amber-400', sign: '±', icon: RefreshCw },
  CONCESSION_APPLIED: { label: 'Concession', color: 'text-purple-400', sign: '−', icon: BadgePercent },
  LATE_FEE: { label: 'Late Fee', color: 'text-red-400', sign: '+', icon: AlertCircle },
};

const PAYMENT_MODES = ['CASH', 'UPI', 'NEFT', 'RTGS', 'CHEQUE', 'DD', 'ONLINE_GATEWAY'];


// =============================================================================
// State badge
// =============================================================================

function StateBadge({ state }) {
  const meta = STATE_META[state] || { label: state, color: 'text-slate-400 border-slate-400/20 bg-slate-400/5', icon: Clock };
  const Icon = meta.icon;
  return (
    <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full border text-[10px] font-mono font-bold uppercase tracking-widest ${meta.color}`}>
      <Icon size={10} />
      {meta.label}
    </span>
  );
}

// =============================================================================
// Outstanding summary strip
// =============================================================================

function SummaryStrip({ summary, loading }) {
  if (loading) return (
    <div className="grid grid-cols-4 gap-4 mb-8">
      {[...Array(4)].map((_, i) => (
        <div key={i} className="bg-navy-lighter/40 border border-gold/10 rounded-2xl p-5 animate-pulse h-24" />
      ))}
    </div>
  );
  if (!summary) return null;
  const tiles = [
    { label: 'Total Demanded', value: fmt(summary.total_demanded), icon: IndianRupee, color: 'text-slate-300' },
    { label: 'Collected', value: fmt(summary.total_collected), icon: CheckCircle2, color: 'text-emerald-400' },
    { label: 'Outstanding', value: fmt(summary.total_outstanding), icon: TrendingDown, color: 'text-amber-400' },
    { label: 'Overdue Accounts', value: summary.overdue_count, icon: AlertCircle, color: 'text-red-400' },
  ];
  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
      {tiles.map(t => (
        <div key={t.label} className="bg-navy-lighter/40 border border-gold/10 rounded-2xl p-5 flex flex-col gap-2 hover:border-gold/30 transition-all">
          <t.icon size={16} className={t.color} />
          <p className="text-2xl font-serif font-bold text-white">{t.value}</p>
          <p className="text-[10px] font-mono uppercase tracking-widest text-slate-500">{t.label}</p>
        </div>
      ))}
    </div>
  );
}

// =============================================================================
// Payment modal
// =============================================================================

function PaymentModal({ demandId, onClose, onSuccess, onNotify }) {
  const [form, setForm] = useState({ amount: '', payment_mode: 'UPI', transaction_ref: '', payment_date: new Date().toISOString().split('T')[0], remarks: '' });
  const [loading, setLoading] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await apiFetch(`/fees/demands/${demandId}/pay`, {
        method: 'POST',
        body: JSON.stringify({ ...form, entry_type: 'PAYMENT', amount: parseFloat(form.amount) }),
      });
      onNotify(`Payment recorded — Receipt ${res.receipt_sequence}`, 'success');
      onSuccess();
    } catch (err) {
      onNotify(err.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-navy/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-navy-lighter border border-gold/20 rounded-3xl p-8 w-full max-w-md shadow-2xl">
        <div className="flex items-center justify-between mb-6">
          <h3 className="font-serif font-bold text-xl text-white flex items-center gap-3">
            <Receipt size={20} className="text-gold" /> Record Payment
          </h3>
          <button onClick={onClose} className="text-slate-500 hover:text-white transition-colors"><X size={18} /></button>
        </div>
        <form onSubmit={submit} className="space-y-4">
          <div>
            <label className="block text-[10px] font-mono uppercase tracking-widest text-slate-500 mb-2">Amount (₹)</label>
            <input required type="number" min="1" step="0.01" value={form.amount} onChange={e => setForm(f => ({ ...f, amount: e.target.value }))}
              className="w-full bg-navy-deep border border-gold/10 focus:border-gold/40 rounded-xl px-4 py-3 text-white outline-none transition-all font-bold text-lg" />
          </div>
          <div>
            <label className="block text-[10px] font-mono uppercase tracking-widest text-slate-500 mb-2">Payment Mode</label>
            <select value={form.payment_mode} onChange={e => setForm(f => ({ ...f, payment_mode: e.target.value }))}
              className="w-full bg-navy-deep border border-gold/10 focus:border-gold/40 rounded-xl px-4 py-3 text-white outline-none transition-all">
              {PAYMENT_MODES.map(m => <option key={m} value={m}>{m}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-[10px] font-mono uppercase tracking-widest text-slate-500 mb-2">Transaction Reference</label>
            <input type="text" value={form.transaction_ref} onChange={e => setForm(f => ({ ...f, transaction_ref: e.target.value }))}
              placeholder="UPI ref / cheque no / NEFT UTR"
              className="w-full bg-navy-deep border border-gold/10 focus:border-gold/40 rounded-xl px-4 py-3 text-white outline-none transition-all placeholder:text-slate-600" />
          </div>
          <div>
            <label className="block text-[10px] font-mono uppercase tracking-widest text-slate-500 mb-2">Payment Date</label>
            <input required type="date" value={form.payment_date} onChange={e => setForm(f => ({ ...f, payment_date: e.target.value }))}
              className="w-full bg-navy-deep border border-gold/10 focus:border-gold/40 rounded-xl px-4 py-3 text-white outline-none transition-all" />
          </div>
          <button type="submit" disabled={loading}
            className="w-full py-3.5 bg-gradient-to-r from-gold to-[#9A7B3A] text-navy font-mono font-bold uppercase tracking-widest rounded-xl active:scale-95 transition-all disabled:opacity-50 flex items-center justify-center gap-2">
            {loading ? <Loader2 size={16} className="animate-spin" /> : <Receipt size={16} />}
            {loading ? 'Processing…' : 'Confirm Payment'}
          </button>
        </form>
      </div>
    </div>
  );
}

// =============================================================================
// Ledger timeline panel
// =============================================================================

function LedgerTimeline({ demand, onPay, onNotify }) {
  const [expanded, setExpanded] = useState(true);
  const bal = demand.balance || {};
  const ledger = demand.ledger || [];

  return (
    <div className="bg-navy-lighter/30 border border-gold/10 rounded-2xl overflow-hidden">
      {/* Header */}
      <div className="p-5 flex items-center justify-between cursor-pointer hover:bg-gold/5 transition-all"
        onClick={() => setExpanded(e => !e)}>
        <div className="flex items-center gap-4">
          <StateBadge state={demand.state} />
          <span className="text-slate-400 text-sm font-mono">{demand.demand_id?.slice(-8)}</span>
        </div>
        <div className="flex items-center gap-6">
          <div className="text-right">
            <p className="text-xs text-slate-500 font-mono">Outstanding</p>
            <p className={`font-serif font-bold text-lg ${bal.outstanding > 0 ? 'text-amber-400' : 'text-emerald-400'}`}>
              {fmt(bal.outstanding)}
            </p>
          </div>
          {expanded ? <ChevronUp size={16} className="text-slate-500" /> : <ChevronDown size={16} className="text-slate-500" />}
        </div>
      </div>

      {expanded && (
        <div className="border-t border-gold/10">
          {/* Balance summary */}
          <div className="grid grid-cols-3 divide-x divide-gold/10 border-b border-gold/10">
            {[
              { label: 'Demanded', value: bal.demanded, color: 'text-slate-300' },
              { label: 'Collected', value: bal.total_paid, color: 'text-emerald-400' },
              { label: 'Outstanding', value: bal.outstanding, color: bal.outstanding > 0 ? 'text-amber-400' : 'text-emerald-400' },
            ].map(c => (
              <div key={c.label} className="p-4 text-center">
                <p className="text-[10px] font-mono uppercase tracking-widest text-slate-600 mb-1">{c.label}</p>
                <p className={`font-bold text-sm ${c.color}`}>{fmt(c.value)}</p>
              </div>
            ))}
          </div>

          {/* Ledger entries */}
          <div className="p-5">
            {ledger.length === 0 ? (
              <p className="text-center text-slate-600 text-sm py-6 font-mono">No payments recorded yet.</p>
            ) : (
              <div className="space-y-3">
                {ledger.map((entry, idx) => {
                  const meta = ENTRY_META[entry.entry_type] || ENTRY_META.PAYMENT;
                  const Icon = meta.icon;
                  return (
                    <div key={idx} className="flex items-center gap-4 p-3 rounded-xl bg-navy-deep/50 hover:bg-navy-deep transition-all">
                      <div className={`w-8 h-8 rounded-lg border flex items-center justify-center flex-shrink-0 ${meta.color} border-current/20 bg-current/5`}>
                        <Icon size={14} />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-bold text-white">{meta.label}</p>
                        <p className="text-[10px] text-slate-600 font-mono truncate">
                          {entry.payment_mode && `${entry.payment_mode} · `}
                          {entry.transaction_ref || entry.receipt_sequence || '—'}
                        </p>
                      </div>
                      <div className="text-right">
                        <p className={`font-bold text-sm ${meta.color}`}>{meta.sign} {fmt(entry.amount)}</p>
                        <p className="text-[10px] text-slate-600 font-mono">{fmtDate(entry.payment_date)}</p>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}

            {/* Record payment CTA */}
            {!['PAID', 'WAIVED', 'REFUNDED'].includes(demand.state) && (
              <button onClick={() => onPay(demand.demand_id)}
                className="mt-4 w-full flex items-center justify-center gap-2 py-3 border border-gold/20 hover:border-gold/60 hover:bg-gold/5 rounded-xl text-gold text-[10px] font-mono uppercase tracking-widest transition-all active:scale-95">
                <Plus size={12} /> Record Payment
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// =============================================================================
// Main FeeLedger component
// =============================================================================

export default function FeeLedger({ onNotify }) {
  const [demands, setDemands] = useState([]);
  const [summary, setSummary] = useState(null);
  const [loadingList, setLoadingList] = useState(true);
  const [loadingSummary, setLoadingSummary] = useState(true);
  const [search, setSearch] = useState('');
  const [stateFilter, setStateFilter] = useState('');
  const [payDemandId, setPayDemandId] = useState(null);
  const [detailMap, setDetailMap] = useState({});
  const [loadingDetail, setLoadingDetail] = useState({});

  const loadSummary = useCallback(async () => {
    setLoadingSummary(true);
    try {
      const res = await apiFetch('/fees/outstanding');
      setSummary(res);
    } catch {
      // non-fatal — admin may not have access
    } finally {
      setLoadingSummary(false);
    }
  }, []);

  const loadDemands = useCallback(async () => {
    setLoadingList(true);
    try {
      const qs = new URLSearchParams({ limit: '50', offset: '0' });
      if (stateFilter) qs.set('state', stateFilter);
      const res = await apiFetch(`/fees/demands?${qs}`);
      setDemands(res);
    } catch (err) {
      onNotify?.(err.message, 'error');
    } finally {
      setLoadingList(false);
    }
  }, [stateFilter, onNotify]);

  const loadDetail = async (demandId) => {
    if (detailMap[demandId]) return;
    setLoadingDetail(prev => ({ ...prev, [demandId]: true }));
    try {
      const d = await apiFetch(`/fees/demands/${demandId}`);
      setDetailMap(prev => ({ ...prev, [demandId]: d }));
    } catch (err) {
      onNotify?.(err.message, 'error');
    } finally {
      setLoadingDetail(prev => ({ ...prev, [demandId]: false }));
    }
  };

  useEffect(() => { loadSummary(); }, [loadSummary]);
  useEffect(() => { loadDemands(); }, [loadDemands]);

  // Auto-load detail for rendered demands
  useEffect(() => {
    demands.forEach(d => { if (!detailMap[d.demand_id]) loadDetail(d.demand_id); });
  }, [demands]);

  const filtered = demands.filter(d =>
    !search || d.demand_id.toLowerCase().includes(search.toLowerCase())
  );

  const handlePaySuccess = () => {
    setPayDemandId(null);
    // Refresh detail and summary
    const id = payDemandId;
    setDetailMap(prev => { const n = { ...prev }; delete n[id]; return n; });
    loadDetail(id);
    loadSummary();
  };

  return (
    <div className="p-6 md:p-10 max-w-5xl mx-auto">
      {/* Header */}
      <div className="mb-8">
        <div className="flex items-center gap-3 mb-2">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-gold/20 to-gold/5 border border-gold/20 flex items-center justify-center">
            <CreditCard size={18} className="text-gold" />
          </div>
          <div>
            <h1 className="font-serif font-black text-3xl text-white">Fee Ledger</h1>
            <p className="text-[10px] font-mono uppercase tracking-widest text-slate-500">
              Additive · Insert-Only · LAW 8 Compliant
            </p>
          </div>
        </div>
      </div>

      {/* Summary strip */}
      <SummaryStrip summary={summary} loading={loadingSummary} />

      {/* Filters */}
      <div className="flex gap-3 mb-6">
        <div className="flex-1 flex items-center gap-3 bg-navy-lighter/40 border border-gold/10 focus-within:border-gold/30 rounded-xl px-4 py-2.5 transition-all">
          <Search size={14} className="text-slate-600" />
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search by demand ID…"
            className="bg-transparent border-none outline-none text-sm text-white placeholder:text-slate-600 flex-1 font-light"
          />
        </div>
        <select
          value={stateFilter}
          onChange={e => setStateFilter(e.target.value)}
          className="bg-navy-lighter/40 border border-gold/10 hover:border-gold/30 rounded-xl px-4 py-2.5 text-sm text-slate-300 outline-none transition-all">
          <option value="">All States</option>
          {Object.entries(STATE_META).map(([k, v]) => (
            <option key={k} value={k}>{v.label}</option>
          ))}
        </select>
      </div>

      {/* Ledger list */}
      {loadingList ? (
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="h-20 bg-navy-lighter/30 border border-gold/10 rounded-2xl animate-pulse" />
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-24 text-slate-600 gap-4">
          <Ban size={40} className="opacity-30" />
          <p className="font-mono text-sm uppercase tracking-widest">No demands found</p>
          {stateFilter && (
            <button onClick={() => setStateFilter('')} className="text-gold/60 hover:text-gold text-xs font-mono transition-colors">
              Clear filter
            </button>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          {filtered.map(d => {
            const detail = detailMap[d.demand_id];
            return (
              <div key={d.demand_id}>
                {loadingDetail[d.demand_id] ? (
                  <div className="h-16 bg-navy-lighter/30 border border-gold/10 rounded-2xl animate-pulse" />
                ) : detail ? (
                  <LedgerTimeline
                    demand={detail}
                    onPay={(id) => setPayDemandId(id)}
                    onNotify={onNotify}
                  />
                ) : (
                  <div className="bg-navy-lighter/30 border border-gold/10 rounded-2xl p-5 flex items-center justify-between">
                    <StateBadge state={d.state} />
                    <span className="text-slate-500 text-xs font-mono">{d.demand_id.slice(-8)}</span>
                    <span className={`font-bold text-sm ${(d.balance?.outstanding ?? 0) > 0 ? 'text-amber-400' : 'text-emerald-400'}`}>
                      {fmt(d.balance?.outstanding)}
                    </span>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Payment modal */}
      {payDemandId && (
        <PaymentModal
          demandId={payDemandId}
          onClose={() => setPayDemandId(null)}
          onSuccess={handlePaySuccess}
          onNotify={onNotify}
        />
      )}
    </div>
  );
}
