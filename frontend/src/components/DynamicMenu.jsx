import React, { useState, useEffect } from 'react';
import { apiFetch } from '../api/client';
import {
    LayoutDashboard,
    FileText,
    Settings,
    ChevronRight,
    ChevronDown,
    Loader2,
    Table,
    ClipboardList,
    Users,
    GraduationCap,
    BookOpen,
    Menu as MenuIcon
} from 'lucide-react';

const iconMap = {
    LayoutDashboard,
    FileText,
    Settings,
    Table,
    ClipboardList,
    Users,
    GraduationCap,
    BookOpen,
    MenuIcon
};

/**
 * DynamicMenu.jsx
 * 
 * Renders a hierarchical menu from backend metadata.
 */
const DynamicMenu = ({ menuCode, onAction, activePath, onNotify }) => {
    const [items, setItems] = useState([]);
    const [loading, setLoading] = useState(true);
    const [openGroups, setOpenGroups] = useState({});

    useEffect(() => {
        async function fetchMenu() {
            try {
                const data = await apiFetch(`/menus/${menuCode}`);
                const map = {};
                const roots = [];
                data.forEach(item => {
                    map[item.item_id] = { ...item, children: [] };
                });
                data.forEach(item => {
                    if (item.parent_item_id) {
                        map[item.parent_item_id]?.children.push(map[item.item_id]);
                    } else {
                        roots.push(map[item.item_id]);
                    }
                });
                setItems(roots);
            } catch (err) {
                onNotify?.(`Failed to load menu: ${err.message}`, 'error');
            } finally {
                setLoading(false);
            }
        }
        fetchMenu();
    }, [menuCode, onNotify]);

    const toggleGroup = (id) => {
        setOpenGroups(prev => ({ ...prev, [id]: !prev[id] }));
    };

    if (loading) return (
        <div className="p-10 flex flex-col items-center gap-4 text-gold/30 animate-pulse font-mono text-[10px] uppercase tracking-[0.3em]">
            <Loader2 className="animate-spin w-6 h-6" />
            Initializing Neural Links...
        </div>
    );

    const renderItem = (item, depth = 0) => {
        const iconName = item.icon_name || 'ChevronRight';
        const Icon = iconMap[iconName] || ChevronRight;
        const isGroup = item.children && item.children.length > 0;
        const isOpen = openGroups[item.item_id];
        const isActive = activePath === item.route_path;

        if (item.action_type === 'DIVIDER') {
            return <div key={item.item_id} className="mx-8 my-6 border-t border-gold/5" />;
        }

        return (
            <div key={item.item_id} className="select-none mb-1.5 px-2">
                <div
                    onClick={() => isGroup ? toggleGroup(item.item_id) : onAction(item)}
                    className={`
                        group flex items-center gap-4 px-6 py-4 rounded-xl cursor-none transition-all duration-500 relative overflow-hidden
                        ${isActive
                            ? 'bg-gold text-navy shadow-gold active-glow'
                            : 'text-slate-400 hover:text-gold hover:bg-gold/5'}
                        ${depth > 0 ? 'ml-8 py-3 opacity-70 hover:opacity-100 scale-95 origin-left' : ''}
                    `}
                >
                    {isActive && (
                        <div className="absolute inset-x-0 bottom-0 h-0.5 bg-navy/20"></div>
                    )}
                    <Icon className={`w-5 h-5 transition-all duration-500 ${isActive ? 'scale-110 rotate-0' : 'group-hover:scale-125 group-hover:rotate-12'}`} />
                    <span className={`flex-1 text-xs tracking-widest uppercase ${isActive ? 'font-black' : 'font-medium'}`}>
                        {item.label}
                    </span>
                    {isGroup && (
                        <div className={`transition-transform duration-500 ${isOpen ? 'rotate-90' : ''}`}>
                            <ChevronRight className={`w-3 h-3 ${isActive ? 'text-navy' : 'text-gold/20'}`} />
                        </div>
                    )}
                </div>
                {isGroup && isOpen && (
                    <div className="mt-2 space-y-1 animate-slide-up">
                        {item.children.map(child => renderItem(child, depth + 1))}
                    </div>
                )}
            </div>
        );
    };

    return (
        <nav className="w-full space-y-1">
            {items.map(item => renderItem(item))}
        </nav>
    );
};

export default DynamicMenu;
