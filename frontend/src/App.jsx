import { useState } from 'react';
import DynamicMenu from './components/DynamicMenu';
import DynamicForm from './components/DynamicForm';
import ReportViewer from './components/ReportViewer';
import WorkflowActions from './components/WorkflowActions';
import { Bell, User, LogOut, Search, Settings, ChevronRight, Menu as MenuIcon, X } from 'lucide-react';

function App() {
  const [activeItem, setActiveItem] = useState(null);
  const [notifications, setNotifications] = useState([]);
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);

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
        <div className="flex flex-col items-center justify-center min-h-[60vh] text-slate-400 p-8">
          <div className="w-24 h-24 bg-white rounded-full flex items-center justify-center shadow-premium mb-6 animate-slide-up">
            <LayoutDashboard size={48} className="text-brand-500/20" />
          </div>
          <h2 className="text-xl font-bold text-slate-900 mb-2">Welcome Back</h2>
          <p className="font-medium text-slate-400 flex items-center gap-2">
            Select a module from the sidebar to start working
          </p>
        </div>
      );
    }

    return (
      <div className="animate-slide-up space-y-8 p-6 md:p-10 max-w-7xl mx-auto">
        <header className="flex flex-col md:flex-row md:items-end justify-between gap-4 border-b border-slate-200 pb-8">
          <div>
            <nav className="flex items-center gap-2 text-xs font-bold text-slate-400 uppercase tracking-widest mb-3">
              <span>Main Console</span>
              <ChevronRight size={12} />
              <span className="text-brand-600">{activeItem.label}</span>
            </nav>
            <h1 className="text-4xl font-extrabold text-slate-900 tracking-tight">{activeItem.label}</h1>
            <p className="mt-2 text-slate-500 font-medium">Manage and track your {activeItem.label.toLowerCase()} efficiently.</p>
          </div>
          <WorkflowActions
            entityCode="ENROLLMENT"
            recordId="00000000-0000-0000-0000-000000000000"
            onNotify={addNotify}
          />
        </header>

        <main className="transition-all duration-300">
          {activeItem.action_type === 'FORM' ? (
            <div className="max-w-4xl mx-auto">
              <DynamicForm formCode={activeItem.action_target} onNotify={addNotify} />
            </div>
          ) : activeItem.action_type === 'REPORT' ? (
            <div className="premium-card overflow-hidden">
              <ReportViewer reportCode={activeItem.action_target} onNotify={addNotify} />
            </div>
          ) : (
            <div className="premium-card p-10 flex flex-col items-center justify-center min-h-[40vh]">
              <div className="w-16 h-16 bg-slate-50 rounded-2xl flex items-center justify-center text-slate-300 mb-4">
                <Settings size={32} />
              </div>
              <p className="text-lg font-semibold text-slate-600">Module Dashboard - {activeItem.label}</p>
              <p className="text-slate-400 mt-2">Route path: {activeItem.route_path}</p>
            </div>
          )}
        </main>
      </div>
    );
  };

  return (
    <div className="flex h-screen bg-[#F8FAFC]">
      {/* Sidebar Overlay for mobile */}
      {!isSidebarOpen && (
        <button
          onClick={() => setIsSidebarOpen(true)}
          className="lg:hidden fixed bottom-6 right-6 w-14 h-14 bg-brand-600 text-white rounded-full shadow-2xl z-50 flex items-center justify-center active:scale-95 transition-all"
        >
          <MenuIcon />
        </button>
      )}

      {/* Sidebar */}
      <aside className={`
        fixed inset-y-0 left-0 z-40 w-80 bg-slate-900 text-white transition-all duration-500 ease-in-out transform
        ${isSidebarOpen ? 'translate-x-0' : '-translate-x-full'}
        lg:translate-x-0 lg:static flex flex-col shadow-2xl
      `}>
        <div className="p-8 pb-10 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 bg-gradient-to-br from-brand-400 to-brand-600 rounded-2xl flex items-center justify-center shadow-lg transform rotate-3 hover:rotate-0 transition-all duration-300">
              <span className="font-black text-xl text-white">P1</span>
            </div>
            <div>
              <h2 className="font-bold text-lg leading-tight tracking-tight">Academy OS</h2>
              <span className="text-[10px] font-black uppercase text-slate-500 tracking-[0.2em]">Kernel v1.0</span>
            </div>
          </div>
          <button onClick={() => setIsSidebarOpen(false)} className="lg:hidden text-slate-500">
            <X size={20} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-4 custom-scrollbar">
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

        <div className="p-6">
          <div className="bg-slate-800/50 backdrop-blur-lg rounded-3xl p-5 border border-slate-700/30">
            <div className="flex items-center gap-4 mb-4">
              <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-slate-700 to-slate-800 border border-slate-600 flex items-center justify-center shadow-sm">
                <User className="text-slate-400 w-6 h-6" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold text-white truncate">Demo User</p>
                <p className="text-xs text-slate-500 font-medium truncate uppercase tracking-wider">Super Admin</p>
              </div>
            </div>
            <button className="w-full flex items-center justify-center gap-2 py-3 bg-slate-800 hover:bg-red-500/10 hover:text-red-500 rounded-2xl text-xs font-bold text-slate-400 transition-all duration-200">
              <LogOut size={14} />
              Sign Out Account
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden relative">
        {/* Header */}
        <header className="h-24 bg-white/80 backdrop-blur-md border-b border-slate-200 flex items-center justify-between px-6 md:px-12 sticky top-0 z-30">
          {!isSidebarOpen && (
            <button onClick={() => setIsSidebarOpen(true)} className="p-3 text-slate-500 hover:bg-slate-50 rounded-2xl transition-all">
              <MenuIcon size={24} />
            </button>
          )}

          <div className="flex-1 flex items-center justify-end md:justify-between gap-8">
            <div className="hidden md:flex items-center flex-1 max-w-md bg-slate-100/50 px-5 py-3 rounded-2xl border border-slate-200 group focus-within:ring-4 focus-within:ring-brand-500/10 focus-within:bg-white focus-within:border-brand-500 transition-all duration-300">
              <Search className="w-5 h-5 text-slate-400 group-focus-within:text-brand-500" />
              <input
                type="text"
                placeholder="Search resources, students, or reports..."
                className="bg-transparent border-none outline-none text-sm w-full ml-3 font-medium placeholder:text-slate-400"
              />
              <span className="text-[10px] font-bold text-slate-400 bg-white px-2 py-1 rounded-lg border border-slate-200 shadow-sm">⌘K</span>
            </div>

            <div className="flex items-center gap-4">
              <button className="p-3 text-slate-500 hover:text-brand-600 hover:bg-brand-50 rounded-2xl transition-all relative group">
                <Bell size={22} />
                <span className="absolute top-3.5 right-3.5 w-2 h-2 bg-brand-500 rounded-full border-2 border-white ring-4 ring-brand-500/20"></span>
              </button>

              <div className="hidden sm:flex flex-col items-end">
                <span className="text-xs font-black text-slate-900 uppercase tracking-tighter leading-none">Management Center</span>
                <span className="text-[10px] font-bold text-green-500 uppercase flex items-center gap-1 mt-1">
                  <span className="w-1.5 h-1.5 bg-green-500 rounded-full"></span>
                  Connected
                </span>
              </div>
            </div>
          </div>
        </header>

        {/* Dynamic Content */}
        <section className="flex-1 overflow-y-auto custom-scrollbar bg-[#F8FAFC]">
          {renderContent()}
        </section>

        {/* Notification Toast Section */}
        <div className="fixed bottom-8 right-8 flex flex-col gap-3 z-50">
          {notifications.map(n => (
            <div
              key={n.id}
              className={`
                px-6 py-4 rounded-3xl shadow-2xl border flex items-center gap-4 animate-slide-up
                ${n.type === 'error' ? 'bg-white border-red-100 text-red-800' :
                  n.type === 'success' ? 'bg-white border-green-100 text-green-800' :
                    'bg-white border-slate-100 text-slate-800 shadow-slate-200/50'}
              `}
            >
              <div className={`w-1.5 h-6 rounded-full ${n.type === 'error' ? 'bg-red-500 shadow-lg shadow-red-200' : n.type === 'success' ? 'bg-green-500 shadow-lg shadow-green-200' : 'bg-brand-500 shadow-lg shadow-brand-200'}`}></div>
              <p className="text-sm font-bold tracking-tight">{n.message}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function LayoutDashboard({ size = 24, className }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className={className}>
      <rect x="3" y="3" width="7" height="7" rx="1.5" /><rect x="14" y="3" width="7" height="7" rx="1.5" />
      <rect x="14" y="14" width="7" height="7" rx="1.5" /><rect x="3" y="14" width="7" height="7" rx="1.5" />
    </svg>
  );
}

export default App;
