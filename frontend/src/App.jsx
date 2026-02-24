/**
 * App.jsx — PrathamOne Academy OS
 *
 * @author    Jawahar R Mallah
 * @role      Founder & Technical Architect
 * @web       https://aiTDL.com | https://pratham1.com
 * @version   Author_Metadata_v1.0
 * @copyright © 2026 Jawahar R Mallah. All rights reserved.
 */
import { useState } from 'react';
import { Routes, Route, useNavigate, Navigate } from 'react-router-dom';
import DynamicMenu from './components/DynamicMenu';
import DynamicForm from './components/DynamicForm';
import ReportViewer from './components/ReportViewer';
import WorkflowActions from './components/WorkflowActions';
import LandingPage from './pages/LandingPage';
import LoginPage from './pages/LoginPage';
import FeeLedger from './components/FeeLedger';
import ProtectedRoute from './components/ProtectedRoute';
import { AuthProvider, useAuth } from './context/AuthContext';
import IntelligenceWidgets from './components/IntelligenceWidgets';
import AttendanceMarker from './components/AttendanceMarker';
import { Bell, User, LogOut, Search, Settings, ChevronRight, Menu as MenuIcon, X, LayoutDashboard } from 'lucide-react';

function App() {
  return (
    <AuthProvider>
      <Routes>
        <Route path="/" element={<LandingWrapper />} />
        <Route path="/login" element={<LoginPage />} />
        <Route
          path="/dashboard"
          element={
            <ProtectedRoute>
              <Dashboard />
            </ProtectedRoute>
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AuthProvider>
  );
}

function LandingWrapper() {
  const navigate = useNavigate();
  return <LandingPage onEnter={() => navigate('/login')} />;
}

function Dashboard() {
  const [activeItem, setActiveItem] = useState(null);
  const [notifications, setNotifications] = useState([]);
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);
  const { user, logout } = useAuth();

  const addNotify = (message, type = 'info') => {
    const id = Date.now();
    setNotifications(prev => [...prev, { id, message, type }]);
    setTimeout(() => {
      setNotifications(prev => prev.filter(n => n.id !== id));
    }, 5000);
  };

  const renderContent = () => {
    if (!activeItem) {
      return (
        <div className="space-y-16 p-6 md:p-12 max-w-7xl mx-auto">
          <header className="flex flex-col md:flex-row md:items-end justify-between gap-6 relative">
            <div>
              <nav className="flex items-center gap-2 text-[10px] font-mono font-medium text-teal-bright uppercase tracking-[0.2em] mb-4">
                <span className="opacity-50 text-white">System</span>
                <ChevronRight size={10} />
                <span>Intelligence Dash</span>
              </nav>
              <h1 className="text-5xl font-serif font-black text-white tracking-tight leading-none mb-3">
                Sovereign Terminal
              </h1>
              <p className="text-slate-400 font-light tracking-wide max-w-lg">
                Authorized access to institutional intelligence. Encrypted data streams active.
              </p>
            </div>
          </header>

          <IntelligenceWidgets />

          <div className="pt-12 border-t border-gold/10">
            <div className="flex flex-col items-center justify-center text-slate-400 p-8 bg-navy-lighter/20 rounded-3xl border border-gold/5 border-dashed">
              <p className="font-mono text-[10px] uppercase tracking-[0.3em] opacity-40">Awaiting module focus</p>
            </div>
          </div>
        </div>
      );
    }

    return (
      <div className="space-y-12 p-6 md:p-12 max-w-7xl mx-auto">
        <header className="flex flex-col md:flex-row md:items-end justify-between gap-6 border-b border-gold/10 pb-12 relative">
          <div className="absolute -left-12 top-0 bottom-0 w-px bg-gradient-to-b from-gold/40 to-transparent hidden xl:block"></div>
          <div>
            <nav className="flex items-center gap-2 text-[10px] font-mono font-medium text-teal-bright uppercase tracking-[0.2em] mb-4">
              <span className="opacity-50 text-white">System</span>
              <ChevronRight size={10} />
              <span>{activeItem.label}</span>
            </nav>
            <h1 className="text-5xl font-serif font-black text-white tracking-tight leading-none mb-3">
              {activeItem.label}
            </h1>
            <p className="text-slate-400 font-light tracking-wide max-w-lg">
              Authorized access to {activeItem.label.toLowerCase()} subsystem. Encrypted data stream active.
            </p>
          </div>
          {/* Workflow actions only shown when a record context is known */}
          {activeItem?.action_type === 'WORKFLOW' && activeItem?.action_target && (
            <div className="relative z-10">
              <WorkflowActions
                entityCode={activeItem.entity_code || 'STUDENT_APPLICATION'}
                recordId={activeItem.action_target}
                onNotify={addNotify}
              />
            </div>
          )}
        </header>

        <main className="transition-all duration-500">
          {activeItem.action_type === 'FORM' ? (
            <div className="max-w-4xl mx-auto">
              <DynamicForm formCode={activeItem.action_target} onNotify={addNotify} />
            </div>
          ) : activeItem.action_type === 'REPORT' ? (
            <div className="premium-card overflow-hidden bg-navy-lighter/40 backdrop-blur-md">
              <ReportViewer reportCode={activeItem.action_target} onNotify={addNotify} />
            </div>
          ) : activeItem.action_type === 'ROUTE' && activeItem.action_target === 'FEE_LEDGER' ? (
            <FeeLedger onNotify={addNotify} />
          ) : activeItem.action_type === 'ROUTE' && activeItem.action_target === 'ATTENDANCE_MARKER' ? (
            <AttendanceMarker onNotify={addNotify} />
          ) : (
            <div className="premium-card p-16 flex flex-col items-center justify-center min-h-[50vh] bg-navy-lighter/30">
              <div className="w-20 h-20 bg-navy-deep border border-gold/10 rounded-2xl flex items-center justify-center text-gold/20 mb-6 shadow-gold">
                <Settings size={40} />
              </div>
              <h3 className="text-2xl font-serif font-bold text-white mb-2">Subsystem Interface</h3>
              <p className="text-slate-400 font-light tracking-wide italic">Route path: {activeItem.route_path}</p>
            </div>
          )}
        </main>
      </div>
    );
  };

  return (
    <div className="flex h-screen bg-navy selection:bg-gold/20 selection:text-white">
      {/* Sidebar Overlay for mobile */}
      {!isSidebarOpen && (
        <button
          onClick={() => setIsSidebarOpen(true)}
          className="lg:hidden fixed bottom-8 right-8 w-16 h-16 bg-gradient-to-br from-gold to-[#9A7B3A] text-navy rounded-full shadow-gold z-50 flex items-center justify-center active:scale-95 transition-all"
        >
          <MenuIcon />
        </button>
      )}

      {/* Sidebar */}
      <aside className={`
        fixed inset-y-0 left-0 z-40 w-85 bg-navy border-r border-gold/10 transition-all duration-700 ease-in-out transform
        ${isSidebarOpen ? 'translate-x-0' : '-translate-x-full'}
        lg:translate-x-0 lg:static flex flex-col shadow-2xl relative
      `}>
        {/* Subtle grid pattern for sidebar */}
        <div className="absolute inset-0 opacity-[0.03] pointer-events-none bg-[url('https://www.transparenttextures.com/patterns/carbon-fibre.png')]"></div>

        <div className="p-10 pb-12 flex items-center justify-between relative z-10">
          <div className="flex items-center gap-5 cursor-pointer" onClick={() => navigate('/')}>
            <div className="w-14 h-14 bg-gradient-to-br from-gold/80 to-[#9A7B3A] rounded-xl flex items-center justify-center shadow-gold transform rotate-3 hover:rotate-0 transition-all duration-500">
              <span className="font-serif font-black text-2xl text-navy">P1</span>
            </div>
            <div>
              <h2 className="font-serif font-bold text-xl leading-tight tracking-tight text-white">Academy OS</h2>
              <span className="text-[10px] font-mono font-medium uppercase text-gold/40 tracking-[0.3em]">Kernel v1.0.4</span>
            </div>
          </div>
          <button onClick={() => setIsSidebarOpen(false)} className="lg:hidden text-gold/40 hover:text-gold transition-colors">
            <X size={20} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-6 custom-scrollbar relative z-10">
          <DynamicMenu
            menuCode="SIDEBAR_NAV"
            onAction={(item) => {
              setActiveItem(item);
              if (window.innerWidth < 1024) setIsSidebarOpen(false);
            }}
            activePath={activeItem?.route_path}
            onNotify={addNotify}
          />
        </div>

        <div className="p-8 relative z-10">
          <div className="bg-navy-lighter/60 backdrop-blur-xl rounded-2xl p-6 border border-gold/10 hover:border-gold/30 transition-all group">
            <div className="flex items-center gap-4 mb-5">
              <div className="w-12 h-12 rounded-xl bg-navy-deep border border-gold/10 flex items-center justify-center transition-all group-hover:border-gold/30 group-hover:shadow-gold">
                <User className="text-gold/40 w-6 h-6 group-hover:text-gold transition-colors" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold text-white truncate">{user?.userId?.slice(-8) ?? 'Principal'}</p>
                <p className="text-[10px] text-gold/40 font-mono font-medium uppercase tracking-[0.1em] mt-0.5">{user?.role ?? 'app_user'}</p>
              </div>
            </div>
            <button
              onClick={logout}
              className="w-full flex items-center justify-center gap-2 py-3 bg-navy-deep border border-gold/10 hover:border-red-500/30 hover:text-red-500 rounded-xl text-[10px] font-mono font-bold text-slate-500 uppercase tracking-widest transition-all duration-300 active:scale-95"
            >
              <LogOut size={12} />
              Terminate Session
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden relative">
        <div className="absolute inset-0 bg-navy opacity-50 z-0 pointer-events-none"></div>

        {/* Header */}
        <header className="h-24 bg-navy/80 backdrop-blur-2xl border-b border-gold/10 flex items-center justify-between px-8 md:px-16 sticky top-0 z-30">
          {!isSidebarOpen && (
            <button onClick={() => setIsSidebarOpen(true)} className="p-3 text-gold/40 hover:text-gold hover:bg-gold/5 rounded-xl transition-all">
              <MenuIcon size={24} />
            </button>
          )}

          <div className="flex-1 flex items-center justify-end md:justify-between gap-12">
            <div className="hidden md:flex items-center flex-1 max-w-lg bg-navy-deep/50 px-6 py-3.5 rounded-xl border border-gold/10 group focus-within:ring-4 focus-within:ring-gold/5 focus-within:bg-navy-deep focus-within:border-gold/30 transition-all duration-500">
              <Search className="w-5 h-5 text-gold/30 group-focus-within:text-gold transition-colors" />
              <input
                type="text"
                placeholder="Query system registry, students, or intelligence..."
                className="bg-transparent border-none outline-none text-sm w-full ml-4 font-light text-cream placeholder:text-slate-600 tracking-wide"
              />
              <span className="text-[9px] font-mono font-bold text-gold/30 bg-navy/50 px-2 py-1.5 rounded-lg border border-gold/10 shadow-sm ml-2">HEX_MODIFIED</span>
            </div>

            <div className="flex items-center gap-6">
              <button className="p-3 text-gold/30 hover:text-gold hover:bg-gold/5 rounded-xl transition-all relative group">
                <Bell size={22} className="group-hover:animate-pulse" />
                <span className="absolute top-3.5 right-3.5 w-2 h-2 bg-gold bright rounded-full border-2 border-navy ring-4 ring-gold/10"></span>
              </button>

              <div className="hidden sm:flex flex-col items-end">
                <span className="text-[10px] font-mono font-black text-white uppercase tracking-[0.2em] leading-none mb-1.5">Sovereign Cortex</span>
                <span className="text-[10px] font-mono font-bold text-teal-bright uppercase flex items-center gap-2 mt-0.5">
                  <span className="w-1.5 h-1.5 bg-teal-bright rounded-full animate-pulse"></span>
                  Node Secure
                </span>
              </div>
            </div>
          </div>
        </header>

        {/* Dynamic Content */}
        <section className="flex-1 overflow-y-auto custom-scrollbar bg-navy relative z-10">
          {renderContent()}
        </section>

        {/* Notification Toast Section */}
        <div className="fixed bottom-10 right-10 flex flex-col gap-4 z-50">
          {notifications.map(n => (
            <div
              key={n.id}
              className={`
                px-8 py-5 rounded-2xl shadow-gold border backdrop-blur-2xl flex items-center gap-5 animate-slide-up
                ${n.type === 'error' ? 'bg-navy-lighter/90 border-red-500/20 text-red-200' :
                  n.type === 'success' ? 'bg-navy-lighter/90 border-teal-bright/20 text-teal-bright shadow-teal/10' :
                    'bg-navy-lighter/90 border-gold/20 text-gold-soft shadow-gold/10'}
              `}
            >
              <div className={`w-1 h-8 rounded-full ${n.type === 'error' ? 'bg-red-500' : n.type === 'success' ? 'bg-teal-bright shadow-[0_0_10px_rgba(34,211,238,0.5)]' : 'bg-gold shadow-[0_0_10px_rgba(201,168,76,0.5)]'}`}></div>
              <p className="text-xs font-mono font-bold tracking-widest uppercase">{n.message}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function LayoutDashboard({ size = 24, className }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className={className}>
      <rect x="3" y="3" width="7" height="7" rx="1" /><rect x="14" y="3" width="7" height="7" rx="1" />
      <rect x="14" y="14" width="7" height="7" rx="1" /><rect x="3" y="14" width="7" height="7" rx="1" />
    </svg>
  );
}

export default App;
