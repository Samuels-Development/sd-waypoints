import React, { useState, useEffect } from 'react';
import './App.css';
import WaypointMarker from './components/WaypointMarker';

interface DUIMessage {
  action: string;
  data?: {
    distance?: string;
    unit?: string;
    color?: string;
    label?: string;
  };
}

const App: React.FC = () => {
  const [visible, setVisible] = useState(false);
  const [distance, setDistance] = useState('0');
  const [unit, setUnit] = useState('M');
  const [color, setColor] = useState('#FFD700');
  const [label, setLabel] = useState('WAYPOINT');

  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      let message: DUIMessage;

      try {
        if (typeof event.data === 'string') {
          message = JSON.parse(event.data);
        } else {
          message = event.data;
        }
      } catch (e) {
        return;
      }

      const { action, data } = message;

      switch (action) {
        case 'show':
          setVisible(true);
          break;
        case 'hide':
          setVisible(false);
          break;
        case 'updateDistance':
          if (data?.distance !== undefined) {
            setDistance(data.distance);
          }
          if (data?.unit !== undefined) {
            setUnit(data.unit);
          }
          break;
        case 'config':
          if (data?.color !== undefined) {
            setColor(data.color);
          }
          if (data?.label !== undefined) {
            setLabel(data.label);
          }
          break;
      }
    };

    window.addEventListener('message', handleMessage);

    return () => {
      window.removeEventListener('message', handleMessage);
    };
  }, []);

  return (
    <div className="app">
      <WaypointMarker
        visible={visible}
        distance={distance}
        unit={unit}
        color={color}
        label={label}
      />
    </div>
  );
};

export default App;
