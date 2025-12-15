import React from 'react';
import './WaypointMarker.css';

interface WaypointMarkerProps {
  visible: boolean;
  distance: string;
  unit: string;
  color: string;
  label: string;
  style: 'classic' | 'modern' | 'elegant';
}

const WaypointMarker: React.FC<WaypointMarkerProps> = ({ visible, distance, unit, color, label, style }) => {
  if (!visible) return null;

  if (style === 'modern') {
    return (
      <div className="waypoint-container waypoint-modern">
        <div className="modern-badge">
          <div className="modern-upper" style={{ borderColor: color }}>
            <div className="modern-content">
              <span className="modern-distance">{distance}</span>
              <span className="modern-unit" style={{ color }}>{unit}</span>
            </div>
            <div className="modern-divider">
              <div className="modern-divider-line" style={{ backgroundColor: color }}></div>
              <div className="modern-divider-dots">
                <div className="modern-dot" style={{ backgroundColor: color }}></div>
                <div className="modern-dot" style={{ backgroundColor: color }}></div>
                <div className="modern-dot" style={{ backgroundColor: color }}></div>
              </div>
            </div>
          </div>
          <div className="modern-label-container" style={{ backgroundColor: color }}>
            <span className="modern-label">{label}</span>
          </div>
        </div>
        <div className="modern-pointer-container">
          <div className="modern-pointer-accent" style={{ backgroundColor: color }}></div>
          <div className="modern-pointer">
            <svg viewBox="0 0 22 14" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M11 14L0 0H22L11 14Z" fill={color} />
            </svg>
          </div>
        </div>
      </div>
    );
  }

  if (style === 'elegant') {
    return (
      <div className="waypoint-container waypoint-elegant">
        <div className="elegant-frame">
          <div className="elegant-corner elegant-corner-tl" style={{ borderColor: color }}></div>
          <div className="elegant-corner elegant-corner-tr" style={{ borderColor: color }}></div>
          <div className="elegant-corner elegant-corner-bl" style={{ borderColor: color }}></div>
          <div className="elegant-corner elegant-corner-br" style={{ borderColor: color }}></div>
          <div className="elegant-inner">
            <div className="elegant-glow-top" style={{ backgroundColor: color }}></div>
            <div className="elegant-glow-bottom" style={{ backgroundColor: color }}></div>
            <div className="elegant-content">
              <div className="elegant-distance-row">
                <span className="elegant-distance">{distance}</span>
                <span className="elegant-unit" style={{ color }}>{unit}</span>
              </div>
              <div className="elegant-separator">
                <div className="elegant-line"></div>
                <div className="elegant-diamond" style={{ borderColor: color }}></div>
                <div className="elegant-line"></div>
              </div>
              <span className="elegant-label">{label}</span>
            </div>
          </div>
        </div>
        <div className="elegant-pointer">
          <svg viewBox="0 0 24 14" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M12 14L0 0H24L12 14Z" fill={color} stroke="#000" strokeWidth="1"/>
          </svg>
        </div>
      </div>
    );
  }

  // Classic style (default)
  return (
    <div className="waypoint-container waypoint-classic">
      <div className="waypoint-content">
        <div className="waypoint-distance">
          <span className="distance-value">{distance}</span>
          <span className="distance-unit" style={{ color }}>{unit}</span>
        </div>
        <div className="waypoint-divider"></div>
        <span className="waypoint-label">{label}</span>
      </div>
      <div className="waypoint-pointer">
        <svg viewBox="0 0 24 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M12 16L2 2H22L12 16Z" fill={color} stroke="#000" strokeWidth="1"/>
        </svg>
      </div>
    </div>
  );
};

export default WaypointMarker;
