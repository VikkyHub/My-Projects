import { Navigate, Route, Routes } from "react-router-dom";
import { hasSession } from "./api/client";
import Home from "./pages/Home";
import Interests from "./pages/Interests";
import Matches from "./pages/Matches";
import Messages from "./pages/Messages";
import ProfileView from "./pages/ProfileView";
import Login from "./pages/Login";
import Register from "./pages/Register";

function RequireAuth({ children }: { children: React.ReactNode }) {
  return hasSession() ? children : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={hasSession() ? <Navigate to="/" replace /> : <Login />} />
      <Route path="/register" element={<RequireAuth><Register /></RequireAuth>} />
      <Route path="/" element={<RequireAuth><Home /></RequireAuth>} />
      <Route path="/matches" element={<RequireAuth><Matches /></RequireAuth>} />
      <Route path="/p/:publicId" element={<RequireAuth><ProfileView /></RequireAuth>} />
      <Route path="/interests" element={<RequireAuth><Interests /></RequireAuth>} />
      <Route path="/messages" element={<RequireAuth><Messages /></RequireAuth>} />
      <Route path="/messages/:convId" element={<RequireAuth><Messages /></RequireAuth>} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
