import { Navigate, Route, Routes } from "react-router-dom";
import { hasSession } from "./api/client";
import AdminLogin from "./admin/AdminLogin";
import AuditPage from "./admin/AuditPage";
import Dashboard from "./admin/Dashboard";
import PhotosPage from "./admin/PhotosPage";
import ProfileDetailPage from "./admin/ProfileDetailPage";
import ProfilesPage from "./admin/ProfilesPage";
import ReportsPage from "./admin/ReportsPage";
import StaffPage from "./admin/StaffPage";
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
      {/* Staff area: separate login + session (see api/client.ts) */}
      <Route path="/admin/login" element={<AdminLogin />} />
      <Route path="/admin" element={<Dashboard />} />
      <Route path="/admin/profiles" element={<ProfilesPage />} />
      <Route path="/admin/profiles/:publicId" element={<ProfileDetailPage />} />
      <Route path="/admin/photos" element={<PhotosPage />} />
      <Route path="/admin/reports" element={<ReportsPage />} />
      <Route path="/admin/audit" element={<AuditPage />} />
      <Route path="/admin/staff" element={<StaffPage />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
