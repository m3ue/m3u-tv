import React, { createContext, useContext, useState, useCallback } from 'react';

interface MenuContextType {
  isExpanded: boolean;
  setExpanded: (expanded: boolean) => void;
  toggleExpanded: () => void;
  isSidebarActive: boolean;
  setSidebarActive: (active: boolean) => void;
}

const MenuContext = createContext<MenuContextType | undefined>(undefined);

export const MenuProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isExpanded, setIsExpanded] = useState(false);
  const [isSidebarActive, setIsSidebarActive] = useState(false);

  const setExpanded = useCallback((expanded: boolean) => {
    setIsExpanded(expanded);
  }, []);

  const toggleExpanded = useCallback(() => {
    setIsExpanded((prev) => !prev);
  }, []);

  const setSidebarActive = useCallback((active: boolean) => {
    setIsSidebarActive(active);
  }, []);

  return (
    <MenuContext.Provider
      value={{
        isExpanded,
        setExpanded,
        toggleExpanded,
        isSidebarActive,
        setSidebarActive,
      }}
    >
      {children}
    </MenuContext.Provider>
  );
};

export const useMenu = () => {
  const context = useContext(MenuContext);
  if (!context) {
    throw new Error('useMenu must be used within a MenuProvider');
  }
  return context;
};
