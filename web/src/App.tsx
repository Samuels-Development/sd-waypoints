import React, { useState, useEffect } from 'react';
import './App.css';
import WaypointMarker from './components/WaypointMarker';

interface DUIMessage {
  action: string;
  data?: {
    distance?: string;
    unit?: string;
  };
}

const App: React.FC = () => {
  const [visible, setVisible] = useState(false);
  const [distance, setDistance] = useState('0');
  const [unit, setUnit] = useState('M');

  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      // DUI messages come as JSON strings that need to be parsed
      let message: DUIMessage;

      try {
        if (typeof event.data === 'string') {
          message = JSON.parse(event.data);
        } else {
          message = event.data;
        }
      } catch (e) {
        return; // Ignore non-JSON messages
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
      />
    </div>
  );
};

export default App;
