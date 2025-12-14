import React from 'react';
import './WaypointMarker.css';

interface WaypointMarkerProps {
  visible: boolean;
  distance: string;
  unit: string;
}

const WaypointMarker: React.FC<WaypointMarkerProps> = ({ visible, distance, unit }) => {
  if (!visible) return null;

  return (
    <div className="waypoint-container">
      <div className="waypoint-content">
        <div className="waypoint-distance">
          <span className="distance-value">{distance}</span>
          <span className="distance-unit">{unit}</span>
        </div>
        <div className="waypoint-divider"></div>
        <span className="waypoint-label">WAYPOINT</span>
      </div>
      <div className="waypoint-pointer">
        <svg viewBox="0 0 24 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M12 16L2 2H22L12 16Z" fill="#FFD700" stroke="#000" strokeWidth="1"/>
        </svg>
      </div>
    </div>
  );
};

export default WaypointMarker;
