import axios, { AxiosInstance, InternalAxiosRequestConfig, AxiosResponse, AxiosError } from 'axios';
import toast from 'react-hot-toast';

// Create axios instance
const api: AxiosInstance = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '/api',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  },
  withCredentials: true // Send cookies with cross-origin requests
});

// Request interceptor - include CSRF token
api.interceptors.request.use(
  (config: InternalAxiosRequestConfig): InternalAxiosRequestConfig => {
    const cookies = document.cookie.split('; ');
    const csrfToken = cookies.find(row => row.startsWith('csrf-token='))?.split('=')[1];
    
    if (csrfToken) {
      config.headers['x-csrf-token'] = csrfToken;
    }
    
    return config;
  },
  (error: AxiosError): Promise<never> => {
    return Promise.reject(error);
  }
);

// Response interceptor - handle errors
api.interceptors.response.use(
  (response: AxiosResponse): AxiosResponse => response,
  (error: AxiosError): Promise<never> => {
    if (error.response?.status === 401) {
      // Unauthorized - session expired or not logged in
      localStorage.removeItem('miniERP-user');
      
      // Only redirect if not already on login page to prevent loops
      if (!window.location.pathname.includes('/login')) {
        window.location.href = '/login';
      }
    } else if (error.response?.status === 403) {
      // Forbidden - insufficient permissions
      const errorMsg = (error.response?.data as { error?: string })?.error
        || 'Access denied. You do not have permission to perform this action.';
      toast.error(errorMsg, { id: 'permission-denied', duration: 5000 });
    }
    return Promise.reject(error);
  }
);

export default api;
