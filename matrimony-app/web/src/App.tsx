import { Navigate, Route, Routes } from "react-router-dom";
import { hasSession } from "./api/client";
import Home from "./pages/Home";
import Login from "./pages/Login";

function RequireAuth({ children }: { children: React.ReactNode }) {
  return hasSession() ? children : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <Home />
          </RequireAuth>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
