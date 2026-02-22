/**
 * LandingPage.jsx — PrathamOne Academy OS
 *
 * @author    Jawahar R Mallah
 * @role      Founder & Technical Architect
 * @web       https://aiTDL.com | https://pratham1.com
 * @version   Author_Metadata_v1.0
 * @copyright © 2026 Jawahar R Mallah. All rights reserved.
 */
import { motion } from 'framer-motion';
import { ChevronRight, Shield, Zap, Database, Layers, ArrowRight, Play, Globe, Cpu } from 'lucide-react';

const LandingPage = ({ onEnter }) => {
    const fadeInUp = {
        initial: { opacity: 0, y: 60 },
        animate: { opacity: 1, y: 0 },
        transition: { duration: 0.8, ease: [0.6, -0.05, 0.01, 0.99] }
    };

    const stagger = {
        animate: {
            transition: {
                staggerChildren: 0.1
            }
        }
    };

    return (
        <div className="min-h-screen bg-navy text-cream selection:bg-gold/30 overflow-x-hidden">
            {/* Mesh Background */}
            <div className="fixed inset-0 mesh-gradient opacity-30 pointer-events-none z-0"></div>

            {/* Navigation */}
            <nav className="fixed top-0 w-full z-50 px-6 md:px-12 py-6">
                <div className="max-w-7xl mx-auto flex items-center justify-between bg-navy-lighter/40 backdrop-blur-2xl border border-gold/10 rounded-2xl px-6 py-4 shadow-2xl">
                    <div className="flex items-center gap-3">
                        <div className="w-10 h-10 bg-gradient-to-br from-gold to-[#9A7B3A] rounded-lg flex items-center justify-center shadow-gold">
                            <span className="font-serif font-black text-navy text-lg">P1</span>
                        </div>
                        <span className="font-serif font-bold text-xl tracking-tight text-white hidden sm:block">PrathamOne</span>
                    </div>

                    <div className="hidden md:flex items-center gap-8 text-[10px] font-mono font-bold uppercase tracking-[0.2em] text-gold/60">
                        <a href="#features" className="hover:text-gold transition-colors">Infrastructure</a>
                        <a href="#tech" className="hover:text-gold transition-colors">Subsystems</a>
                        <a href="#about" className="hover:text-gold transition-colors">Philosophy</a>
                    </div>

                    <button
                        onClick={onEnter}
                        className="group flex items-center gap-2 bg-gold/5 hover:bg-gold/10 border border-gold/20 hover:border-gold px-5 py-2.5 rounded-xl transition-all active:scale-95"
                    >
                        <span className="text-[10px] font-mono font-black uppercase tracking-widest text-gold text-shadow-gold">Access Terminal</span>
                        <ArrowRight size={14} className="text-gold group-hover:translate-x-1 transition-transform" />
                    </button>
                </div>
            </nav>

            {/* Hero Section */}
            <main className="relative z-10 pt-48 pb-24 px-6">
                <div className="max-w-7xl mx-auto text-center">
                    <motion.div
                        initial={{ opacity: 0, scale: 0.9 }}
                        animate={{ opacity: 1, scale: 1 }}
                        transition={{ duration: 1 }}
                        className="inline-flex items-center gap-2 px-4 py-2 bg-navy-lighter/50 border border-gold/10 rounded-full mb-8"
                    >
                        <span className="w-2 h-2 bg-teal-bright rounded-full animate-pulse shadow-[0_0_10px_#22d3ee]"></span>
                        <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-gold/60">Kernel v1.0.4 Deploying</span>
                    </motion.div>

                    <motion.h1
                        initial={{ opacity: 0, y: 40 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.8, delay: 0.2 }}
                        className="text-6xl md:text-8xl lg:text-9xl font-serif font-black leading-[0.9] tracking-tighter text-white mb-8"
                    >
                        Sovereign <br />
                        <span className="text-gradient">Intelligence.</span>
                    </motion.h1>

                    <motion.p
                        initial={{ opacity: 0, y: 20 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.8, delay: 0.4 }}
                        className="max-w-2xl mx-auto text-lg md:text-xl font-light text-slate-400 mb-12"
                    >
                        The world's most modular Academy OS. Built on the core laws of performance,
                        privacy, and declarative power.
                    </motion.p>

                    <motion.div
                        initial={{ opacity: 0, y: 20 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.8, delay: 0.6 }}
                        className="flex flex-col sm:flex-row items-center justify-center gap-6"
                    >
                        <button
                            onClick={onEnter}
                            className="group relative px-8 py-5 bg-gradient-to-br from-gold to-[#9A7B3A] rounded-2xl font-bold text-navy text-sm uppercase tracking-widest shadow-[0_20px_50px_rgba(201,168,76,0.3)] hover:shadow-[0_20px_80px_rgba(201,168,76,0.5)] transition-all active:scale-95 flex items-center gap-3 overflow-hidden"
                        >
                            <div className="absolute inset-0 bg-white/20 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700 ease-in-out"></div>
                            <span>Launch Subsystem</span>
                            <Play size={16} fill="currentColor" />
                        </button>
                        <button className="px-8 py-5 bg-navy-lighter/30 hover:bg-navy-lighter/50 border border-gold/10 rounded-2xl font-bold text-gold/80 text-sm uppercase tracking-widest backdrop-blur-xl transition-all active:scale-95">
                            Kernel Docs
                        </button>
                    </motion.div>
                </div>

                {/* Hero Illustration */}
                <motion.div
                    initial={{ opacity: 0, y: 100 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 1.2, delay: 0.8 }}
                    className="mt-32 max-w-6xl mx-auto relative group"
                >
                    <div className="absolute -inset-10 bg-gold/10 rounded-[4rem] blur-[8rem] group-hover:bg-gold/20 transition-all duration-1000"></div>
                    <div className="relative bg-navy-deep border border-gold/20 rounded-[3rem] overflow-hidden shadow-2xl overflow-hidden aspect-video transform hover:scale-[1.02] transition-transform duration-700">
                        <div className="absolute inset-0 bg-gradient-to-t from-navy via-transparent to-transparent z-10"></div>
                        {/* Mock system UI */}
                        <div className="p-12 opacity-40">
                            <div className="flex gap-4 mb-12">
                                <div className="w-3 h-3 rounded-full bg-red-500/50"></div>
                                <div className="w-3 h-3 rounded-full bg-yellow-500/50"></div>
                                <div className="w-3 h-3 rounded-full bg-green-500/50"></div>
                            </div>
                            <div className="space-y-6">
                                <div className="h-8 bg-gold/10 rounded-lg w-1/3 animate-pulse"></div>
                                <div className="h-32 bg-gold/5 rounded-2xl w-full"></div>
                                <div className="grid grid-cols-3 gap-6">
                                    <div className="h-48 bg-gold/5 rounded-2xl"></div>
                                    <div className="h-48 bg-gold/5 rounded-2xl"></div>
                                    <div className="h-48 bg-gold/5 rounded-2xl"></div>
                                </div>
                            </div>
                        </div>
                        <div className="absolute inset-0 flex items-center justify-center z-20">
                            <div className="text-center">
                                <div className="w-24 h-24 bg-gold/10 rounded-3xl border border-gold/30 flex items-center justify-center mb-6 mx-auto animate-float">
                                    <Cpu size={48} className="text-gold animate-pulse-gold" />
                                </div>
                                <h3 className="text-gold font-mono text-sm tracking-[0.5em] uppercase">Kernel Interface Active</h3>
                            </div>
                        </div>
                    </div>
                </motion.div>
            </main>

            {/* Feature Bento Grid */}
            <section id="features" className="relative z-10 py-32 px-6">
                <div className="max-w-7xl mx-auto">
                    <div className="mb-24">
                        <h2 className="text-4xl md:text-6xl font-serif font-black text-white mb-6">Designed for <br /><span className="text-gold/50 tracking-tighter">Total Sovereignty.</span></h2>
                        <p className="text-slate-400 max-w-xl font-light">Precision-engineered layers that provide unparalleled control over your institution's data, workflows, and intelligence.</p>
                    </div>

                    <motion.div
                        variants={stagger}
                        initial="initial"
                        whileInView="animate"
                        viewport={{ once: true }}
                        className="bento-grid"
                    >
                        {/* EAV Engine */}
                        <motion.div
                            variants={fadeInUp}
                            className="col-span-12 md:col-span-8 premium-card p-10 bg-navy-lighter/30 overflow-hidden relative group"
                        >
                            <div className="absolute top-0 right-0 w-64 h-64 bg-gold/5 blur-[5rem] group-hover:bg-gold/10 transition-all"></div>
                            <Database className="text-gold mb-6" size={32} />
                            <h3 className="text-3xl font-serif font-bold text-white mb-4">EAV Schema Engine</h3>
                            <p className="text-slate-400 font-light max-w-sm">No custom columns. No migration debt. Define attributes at runtime and let the kernel handle the rest.</p>
                            <div className="mt-12 flex gap-4">
                                {['Text', 'JSON', 'Vector', 'Blob'].map(tech => (
                                    <span key={tech} className="px-3 py-1 bg-navy-deep border border-gold/10 rounded-full text-[9px] font-mono text-gold/40">{tech}</span>
                                ))}
                            </div>
                        </motion.div>

                        {/* AI Cortex */}
                        <motion.div
                            variants={fadeInUp}
                            className="col-span-12 md:col-span-4 premium-card p-10 bg-navy-lighter/30 flex flex-col justify-between border-teal-bright/10 hover:border-teal-bright/30 transition-all"
                        >
                            <div>
                                <Zap className="text-teal-bright mb-6" size={32} />
                                <h3 className="text-2xl font-serif font-bold text-white mb-4">Sovereign Cortex</h3>
                                <p className="text-slate-400 text-sm font-light">Integrated LLM nodes for automated grading, scheduling, and strategic insights.</p>
                            </div>
                            <div className="mt-8 h-12 flex items-end gap-1">
                                {[40, 70, 45, 90, 65, 80, 50, 95].map((h, i) => (
                                    <motion.div
                                        key={i}
                                        initial={{ height: 0 }}
                                        whileInView={{ height: `${h}%` }}
                                        transition={{ duration: 0.5, delay: i * 0.1 }}
                                        className="flex-1 bg-teal-bright/20 rounded-t-sm"
                                    />
                                ))}
                            </div>
                        </motion.div>

                        {/* Policy Engine */}
                        <motion.div
                            variants={fadeInUp}
                            className="col-span-12 md:col-span-4 premium-card p-10 bg-navy-lighter/30 border-purple-500/10 hover:border-purple-500/30 transition-all"
                        >
                            <Shield className="text-purple-400 mb-6" size={32} />
                            <h3 className="text-2xl font-serif font-bold text-white mb-4">Policy-First Security</h3>
                            <p className="text-slate-400 text-sm font-light">Declarative RLS and JWT-based isolation. Security is a layer, not a feature.</p>
                        </motion.div>

                        {/* Workflow Engine */}
                        <motion.div
                            variants={fadeInUp}
                            className="col-span-12 md:col-span-8 premium-card p-10 bg-navy-lighter/30 overflow-hidden group"
                        >
                            <div className="flex flex-col md:flex-row gap-12 items-center">
                                <div className="flex-1">
                                    <Layers className="text-gold mb-6" size={32} />
                                    <h3 className="text-3xl font-serif font-bold text-white mb-4">State Transition Engine</h3>
                                    <p className="text-slate-400 font-light max-w-sm">Move students, staff, and curriculum through complex, auditable workflows without writing nested if-statements.</p>
                                </div>
                                <div className="flex gap-4 relative">
                                    <motion.div
                                        animate={{ y: [0, -10, 0] }}
                                        transition={{ duration: 3, repeat: Infinity, ease: "easeInOut" }}
                                        className="w-16 h-16 rounded-2xl bg-gold/10 border border-gold/20 flex items-center justify-center font-serif text-gold italic"
                                    >A</motion.div>
                                    <motion.div
                                        animate={{ y: [0, -10, 0] }}
                                        transition={{ duration: 3, repeat: Infinity, ease: "easeInOut", delay: 0.5 }}
                                        className="w-16 h-16 rounded-2xl bg-gold/20 border border-gold/40 flex items-center justify-center font-serif text-gold italic translate-y-4"
                                    >B</motion.div>
                                    <motion.div
                                        animate={{ y: [0, -10, 0] }}
                                        transition={{ duration: 3, repeat: Infinity, ease: "easeInOut", delay: 1 }}
                                        className="w-16 h-16 rounded-2xl bg-gold/30 border border-gold/60 flex items-center justify-center font-serif text-gold italic translate-y-8"
                                    >C</motion.div>
                                </div>
                            </div>
                        </motion.div>
                    </motion.div>
                </div>
            </section>

            {/* Tech Stack */}
            <section id="tech" className="py-32 px-6 bg-navy-deep/30">
                <div className="max-w-7xl mx-auto flex flex-col items-center">
                    <motion.div
                        initial={{ opacity: 0 }}
                        whileInView={{ opacity: 1 }}
                        className="text-center mb-16"
                    >
                        <h4 className="text-[10px] font-mono font-bold uppercase tracking-[0.4em] text-gold/40 mb-4">Engineered Core</h4>
                        <h2 className="text-4xl font-serif font-bold text-white tracking-tight">Built with industrial grade tech.</h2>
                    </motion.div>

                    <div className="grid grid-cols-2 md:grid-cols-4 gap-12 opacity-50 filter grayscale hover:grayscale-0 transition-all duration-700">
                        <div className="flex flex-col items-center gap-4">
                            <Database size={40} className="text-slate-400" />
                            <span className="font-mono text-[10px] tracking-widest text-slate-500 uppercase font-bold">PostgreSQL RLS</span>
                        </div>
                        <div className="flex flex-col items-center gap-4">
                            <Zap size={40} className="text-slate-400" />
                            <span className="font-mono text-[10px] tracking-widest text-slate-500 uppercase font-bold">FastAPI / Python</span>
                        </div>
                        <div className="flex flex-col items-center gap-4">
                            <Globe size={40} className="text-slate-400" />
                            <span className="font-mono text-[10px] tracking-widest text-slate-500 uppercase font-bold">React Framework</span>
                        </div>
                        <div className="flex flex-col items-center gap-4">
                            <Shield size={40} className="text-slate-400" />
                            <span className="font-mono text-[10px] tracking-widest text-slate-500 uppercase font-bold">JWT Security</span>
                        </div>
                    </div>
                </div>
            </section>

            {/* Final CTA */}
            <section className="py-48 px-6 text-center relative overflow-hidden">
                <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[800px] bg-gold/5 blur-[10rem] mask-radial"></div>
                <div className="relative z-10">
                    <h2 className="text-5xl md:text-7xl font-serif font-black text-white mb-8 tracking-tighter">Ready to initialize?</h2>
                    <p className="text-slate-400 mb-12 max-w-lg mx-auto font-light">Join the future of academic management. Deploy your own instance of Academy OS today.</p>
                    <button
                        onClick={onEnter}
                        className="group px-12 py-6 bg-cream text-navy rounded-2xl font-black uppercase tracking-widest shadow-2xl hover:scale-105 transition-all active:scale-95"
                    >
                        Access Sovereign Terminal
                    </button>
                </div>
            </section>

            <footer className="py-12 px-6 border-t border-gold/5">
                <div className="max-w-7xl mx-auto flex flex-col md:flex-row justify-between items-center gap-8 font-mono text-[9px] text-gold/20 uppercase tracking-[0.3em]">
                    <div>© 2026 PrathamOne Academy OS Kernel</div>
                    <div className="flex gap-8">
                        <a href="#" className="hover:text-gold transition-colors">Github</a>
                        <a href="#" className="hover:text-gold transition-colors">Documentation</a>
                        <a href="#" className="hover:text-gold transition-colors">Network Status</a>
                    </div>
                    <div>Authorized Personnel Only</div>
                </div>
            </footer>
        </div>
    );
};

export default LandingPage;
