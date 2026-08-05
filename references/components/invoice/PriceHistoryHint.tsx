import { useState, useEffect, useRef } from 'react';

import { DollarSign, AlertTriangle, Info, ArrowRight, ArrowUp, ArrowDown, Check } from 'lucide-react';

import { useSettings } from '../../context/SettingsContext';
import './PriceHistoryHint.css';

interface PriceHistory {
  last_price: number;
  lowest_price: number;
  highest_price: number;
  customer_name: string;
  invoice_date: string;
  transaction_count: number;
  avg_price: number;
}

interface PriceHistoryHintProps {
  history: PriceHistory;
  currentPrice: number;
  onClose: () => void;
}

export default function PriceHistoryHint({ history, currentPrice, onClose }: PriceHistoryHintProps) {
  const { formatCurrency, settings } = useSettings();
  const [isHovering, setIsHovering] = useState(false);
  const [countdown, setCountdown] = useState<number | null>(() => {
    const value = settings?.tooltip_timeout?.value;
    const parsed = parseInt(value || '10', 10);
    return isNaN(parsed) || parsed < 1 ? 10 : parsed;
  });
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Get timeout from settings (default 10 seconds)
  const getTimeoutSeconds = () => {
    const value = settings?.tooltip_timeout?.value;
    const parsed = parseInt(value || '10', 10);
    return isNaN(parsed) || parsed < 1 ? 10 : parsed;
  };

  // Start the auto-hide timer
  const startTimer = () => {
    const seconds = getTimeoutSeconds();
    setCountdown(seconds);

    // Clear any existing timers
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    if (intervalRef.current) clearInterval(intervalRef.current);

    // Start countdown interval
    intervalRef.current = setInterval(() => {
      setCountdown(prev => {
        if (prev !== null && prev > 1) {
          return prev - 1;
        }
        return prev;
      });
    }, 1000);

    // Set timeout to close
    timeoutRef.current = setTimeout(() => {
      onClose();
    }, seconds * 1000);
  };

  // Stop all timers
  const stopTimer = () => {
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
    setCountdown(null);
  };

  // Start timer on mount — countdown initialized in useState
  useEffect(() => {
    const timeoutSeconds = getTimeoutSeconds();
    
    // Clear any existing timers
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    if (intervalRef.current) clearInterval(intervalRef.current);

    // Start countdown interval
    intervalRef.current = setInterval(() => {
      setCountdown(prev => {
        if (prev !== null && prev > 1) {
          return prev - 1;
        }
        return prev;
      });
    }, 1000);

    // Set timeout to close
    timeoutRef.current = setTimeout(() => {
      onClose();
    }, timeoutSeconds * 1000);

    // Cleanup on unmount
    return () => {
      stopTimer();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Handle mouse enter - pause timer and keep tooltip open
  const handleMouseEnter = (_e: React.MouseEvent) => {
    setIsHovering(true);
    stopTimer(); // Stop the countdown - keep open while hovering
  };

  // Handle mouse leave - close immediately
  const handleMouseLeave = (_e: React.MouseEvent) => {
    setIsHovering(false);
    stopTimer();
    onClose(); // Close immediately when mouse leaves
  };

  // Calculate price difference
  const getPriceDifference = () => {
    if (!history?.last_price || !currentPrice) {
      return null;
    }
    const diff = currentPrice - history.last_price;
    const percentageChange = (diff / history.last_price) * 100;

    return {
      absolute: diff,
      percentage: percentageChange,
      increased: diff > 0,
      decreased: diff < 0,
      same: diff === 0
    };
  };

  const difference = getPriceDifference();

  return (
    <div
      className="price-history-hint"
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      <button
        className="hint-close"
        onClick={onClose}
        aria-label="Close price history"
      >
        ×
      </button>

      <div className="hint-content">
        <div className="hint-header">
          <DollarSign className="hint-icon" size={20} />
          <h4>Price History</h4>
        </div>

        <div className="price-comparison">
          <div className="price-row current-price">
            <span className="price-label">Current Price:</span>
            <span className="price-value">{formatCurrency(currentPrice)}</span>
          </div>

          {history.last_price && (
            <div className="price-row history-price">
              <span className="price-label">Last Sold to {history.customer_name}:</span>
              <span className="price-value">{formatCurrency(history.last_price)}</span>
              {history.invoice_date && (
                <span className="invoice-date">
                  ({new Date(history.invoice_date).toLocaleDateString()})
                </span>
              )}
            </div>
          )}
        </div>

        {difference && (
          <div className={`price-difference ${difference.same ? 'same' : difference.increased ? 'increased' : 'decreased'}`}>
            <span className="diff-icon">
              {difference.same ? <ArrowRight size={16} /> : difference.increased ? <ArrowUp size={16} /> : <ArrowDown size={16} />}
            </span>
            <span className="diff-text">
              {difference.same
                ? 'Same as last price'
                : difference.increased
                ? formatCurrency(Math.abs(difference.absolute)) + ' higher (+' + difference.percentage.toFixed(1) + '%)'
                : formatCurrency(Math.abs(difference.absolute)) + ' lower (-' + Math.abs(difference.percentage).toFixed(1) + '%)'}
            </span>
          </div>
        )}

        {history.transaction_count > 0 && (
          <div className="transaction-info">
            <span className="transaction-count">
              {history.transaction_count} previous transaction{history.transaction_count > 1 ? 's' : ''}
            </span>
            {history.avg_price && (
              <span className="avg-price">
                Avg: {formatCurrency(history.avg_price)}
              </span>
            )}
          </div>
        )}

        {difference && !difference.same && (
          <div className={`price-recommendation ${difference.increased ? 'warning' : 'info'}`}>
            <span className="rec-icon">{difference.increased ? <AlertTriangle size={16} /> : <Info size={16} />}</span>
            <span className="rec-text">
              {difference.increased
                ? 'Price increased. Confirm with customer if this is intentional.'
                : 'Price decreased from last sale. Good deal for customer!'}
            </span>
          </div>
        )}

        {/* Countdown timer - show countdown when not hovering */}
        {isHovering ? (
          <div className="countdown-timer keep-open">
            <Check size={14} className="icon-valign-middle icon-mr-xs" /> Tooltip will stay open while hovering - move mouse away to close
          </div>
        ) : !isHovering && countdown !== null && countdown > 0 ? (
          <div className="countdown-timer">
            Hover over tooltip to keep it open
          </div>
        ) : null}
      </div>
    </div>
  );
}
