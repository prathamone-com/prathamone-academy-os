/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        navy: {
          DEFAULT: '#080E1A',
          lighter: '#0D1B2A',
          deep: '#122338',
        },
        gold: {
          DEFAULT: '#C9A84C',
          bright: '#E8C96A',
          soft: '#F5E0A0',
        },
        teal: {
          DEFAULT: '#0E7490',
          bright: '#22D3EE',
        },
        cream: '#F8F3E8',
        slate: {
          400: '#94A3B8',
        }
      },
      fontFamily: {
        serif: ['Playfair Display', 'serif'],
        sans: ['DM Sans', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
      borderRadius: {
        '2xl': '1rem',
        '3xl': '1.5rem',
        '4xl': '2rem',
      },
      boxShadow: {
        'premium': '0 10px 15px -3px rgba(0, 0, 0, 0.5), 0 4px 6px -2px rgba(0, 0, 0, 0.25)',
        'gold': '0 0 40px rgba(201, 168, 76, 0.25)',
        'gold-hover': '0 0 60px rgba(201, 168, 76, 0.4)',
      }
    },
  },
  plugins: [],
}
