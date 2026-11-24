import { useQuery } from "@tanstack/react-query";
import { api } from "../api/client";
import type { CityOption, Option } from "../api/types";

const STALE = 60 * 60 * 1000; // reference data rarely changes

function useOptions<T = Option>(path: string, enabled = true) {
  return useQuery({
    queryKey: ["master", path],
    queryFn: () => api<T[]>(`/master/${path}`),
    enabled,
    staleTime: STALE,
  });
}

export const useReligions = () => useOptions("religions");
export const useCommunities = (religionId?: number | null) =>
  useOptions(`communities?religion_id=${religionId}`, !!religionId);
export const useSubCommunities = (communityId?: number | null) =>
  useOptions(`sub-communities?community_id=${communityId}`, !!communityId);
export const useMotherTongues = () => useOptions("mother-tongues");
export const useCities = () => useOptions<CityOption>("cities");
export const useEducationLevels = () => useOptions("education-levels");
export const useOccupations = () => useOptions("occupations");

export function nameOf(list: Option[] | undefined, id: number | null | undefined) {
  if (id == null) return undefined;
  return list?.find((o) => o.id === id)?.name;
}
