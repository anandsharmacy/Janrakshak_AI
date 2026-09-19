import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'
import './auth.css'
import { ThemeProvider } from '@/lib/theme'
import { LanguageProvider } from '@/lib/i18n'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ThemeProvider>
      <LanguageProvider>
        <App />
      </LanguageProvider>
    </ThemeProvider>
  </React.StrictMode>,
)
