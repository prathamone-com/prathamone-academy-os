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
        <div className="p-6 flex items-center gap-3 text-slate-500 animate-pulse font-medium text-xs uppercase tracking-widest">
            <Loader2 className="animate-spin w-4 h-4" />
            Syncing Navigation...
        </div>
    );

    const renderItem = (item, depth = 0) => {
        const iconName = item.icon_name || 'ChevronRight';
        const Icon = iconMap[iconName] || ChevronRight;
        const isGroup = item.children && item.children.length > 0;
        const isOpen = openGroups[item.item_id];
        const isActive = activePath === item.route_path;

        if (item.action_type === 'DIVIDER') {
            return <div key={item.item_id} className="mx-6 my-4 border-t border-slate-800/50" />;
        }

        return (
            <div key={item.item_id} className="select-none mb-1">
                <div
                    onClick={() => isGroup ? toggleGroup(item.item_id) : onAction(item)}
                    className={`
                        group flex items-center gap-3 px-6 py-3.5 rounded-2xl cursor-pointer transition-all duration-300
                        ${isActive
                            ? 'bg-brand-600 text-white shadow-lg shadow-brand-500/20 active-glow'
                            : 'text-slate-400 hover:bg-slate-800 hover:text-white'}
                        ${depth > 0 ? 'ml-6 py-2.5 opacity-80 hover:opacity-100' : ''}
                    `}
                >
                    <Icon className={`w-5 h-5 transition-transform duration-300 ${isActive ? 'scale-110' : 'group-hover:scale-110'}`} />
                    <span className={`flex-1 text-sm font-bold tracking-tight ${isActive ? 'font-black' : ''}`}>
                        {item.label}
                    </span>
                    {isGroup && (
                        <div className={`transition-transform duration-300 ${isOpen ? 'rotate-90' : ''}`}>
                            <ChevronRight className={`w-4 h-4 ${isActive ? 'text-white' : 'text-slate-600'}`} />
                        </div>
                    )}
                </div>
                {isGroup && isOpen && (
                    <div className="mt-1 space-y-1 overflow-hidden transition-all duration-500">
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
