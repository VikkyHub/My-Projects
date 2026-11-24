-- PostgreSQL database dump

-- Name: admin_actions; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.admin_actions (
    id bigint NOT NULL,
    admin_id uuid NOT NULL,
    target_type character varying(30) NOT NULL,
    target_id character varying(64) NOT NULL,
    action character varying(40) NOT NULL,
    reason character varying(500),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: admin_actions_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.admin_actions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: admin_actions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.admin_actions_id_seq OWNED BY public.admin_actions.id;

-- Name: alembic_version; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);

-- Name: blocks; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.blocks (
    blocker_id uuid NOT NULL,
    blocked_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: cities; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.cities (
    id integer NOT NULL,
    state_id integer NOT NULL,
    name character varying(80) NOT NULL,
    tier smallint
);

-- Name: cities_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.cities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: cities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.cities_id_seq OWNED BY public.cities.id;

-- Name: communities; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.communities (
    id integer NOT NULL,
    religion_id integer NOT NULL,
    name character varying(120) NOT NULL,
    active boolean NOT NULL
);

-- Name: communities_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.communities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: communities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.communities_id_seq OWNED BY public.communities.id;

-- Name: consents; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.consents (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    purpose character varying(40) NOT NULL,
    version character varying(40) NOT NULL,
    granted boolean NOT NULL,
    ip inet,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: consents_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.consents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: consents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.consents_id_seq OWNED BY public.consents.id;

-- Name: contact_unlocks; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.contact_unlocks (
    viewer_id uuid NOT NULL,
    target_id uuid NOT NULL,
    subscription_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: conversations; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.conversations (
    id uuid NOT NULL,
    interest_id uuid NOT NULL,
    profile_a uuid NOT NULL,
    profile_b uuid NOT NULL,
    status character varying(20) NOT NULL,
    last_message_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: countries; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.countries (
    id integer NOT NULL,
    name character varying(80) NOT NULL,
    iso2 character varying(2) NOT NULL
);

-- Name: countries_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.countries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: countries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.countries_id_seq OWNED BY public.countries.id;

-- Name: daily_matches; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.daily_matches (
    profile_id uuid NOT NULL,
    match_id uuid NOT NULL,
    for_date date NOT NULL,
    score smallint NOT NULL
);

-- Name: devices; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.devices (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    fcm_token character varying(255),
    platform character varying(20),
    fingerprint character varying(128),
    ip inet,
    last_seen_at timestamp with time zone
);

-- Name: education_levels; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.education_levels (
    id integer NOT NULL,
    name character varying(80) NOT NULL,
    rank smallint NOT NULL
);

-- Name: education_levels_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.education_levels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: education_levels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.education_levels_id_seq OWNED BY public.education_levels.id;

-- Name: interests; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.interests (
    id uuid NOT NULL,
    sender_id uuid NOT NULL,
    receiver_id uuid NOT NULL,
    status character varying(20) NOT NULL,
    note character varying(300),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    responded_at timestamp with time zone,
    CONSTRAINT ck_interests_not_self CHECK ((sender_id <> receiver_id))
);

-- Name: messages; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.messages (
    id bigint NOT NULL,
    conversation_id uuid NOT NULL,
    sender_id uuid NOT NULL,
    body text NOT NULL,
    flagged boolean NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_messages_body_len CHECK ((length(body) <= 2000))
);

-- Name: messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.messages_id_seq OWNED BY public.messages.id;

-- Name: mother_tongues; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.mother_tongues (
    id integer NOT NULL,
    name character varying(60) NOT NULL
);

-- Name: mother_tongues_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.mother_tongues_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: mother_tongues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.mother_tongues_id_seq OWNED BY public.mother_tongues.id;

-- Name: occupations; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.occupations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    category character varying(60)
);

-- Name: occupations_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.occupations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: occupations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.occupations_id_seq OWNED BY public.occupations.id;

-- Name: partner_preferences; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.partner_preferences (
    profile_id uuid NOT NULL,
    age_min smallint,
    age_max smallint,
    height_min_cm smallint,
    height_max_cm smallint,
    marital_statuses character varying(20)[],
    religion_ids integer[],
    community_ids integer[],
    mother_tongue_ids integer[],
    city_ids integer[],
    state_ids integer[],
    country_ids integer[],
    min_education_rank smallint,
    min_income_band smallint,
    diets character varying(20)[],
    manglik character varying(20)
);

-- Name: payments; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.payments (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    plan_id integer,
    amount_paise integer NOT NULL,
    currency character varying(3) NOT NULL,
    razorpay_order_id character varying(64) NOT NULL,
    razorpay_payment_id character varying(64),
    status character varying(20) NOT NULL,
    raw_webhook jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    paid_at timestamp with time zone
);

-- Name: photos; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.photos (
    id uuid NOT NULL,
    profile_id uuid NOT NULL,
    storage_key character varying(255) NOT NULL,
    phash bigint,
    is_primary boolean NOT NULL,
    sort smallint NOT NULL,
    status character varying(20) NOT NULL,
    reject_reason character varying(200),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: plans; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.plans (
    id integer NOT NULL,
    code character varying(40) NOT NULL,
    name character varying(60) NOT NULL,
    duration_days integer NOT NULL,
    price_paise integer NOT NULL,
    contact_credits integer NOT NULL,
    can_chat boolean NOT NULL,
    daily_interest_limit integer,
    active boolean NOT NULL
);

-- Name: plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.plans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.plans_id_seq OWNED BY public.plans.id;

-- Name: privacy_settings; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.privacy_settings (
    profile_id uuid NOT NULL,
    photo_visibility character varying(20) NOT NULL,
    contact_visibility character varying(20) NOT NULL,
    show_last_active boolean NOT NULL,
    hidden_from_search boolean NOT NULL
);

-- Name: profile_career; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.profile_career (
    profile_id uuid NOT NULL,
    education_level_id integer,
    education_detail character varying(150),
    college character varying(150),
    occupation_id integer,
    employer character varying(150),
    employed_in character varying(20),
    annual_income_band smallint
);

-- Name: profile_family; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.profile_family (
    profile_id uuid NOT NULL,
    father_occupation character varying(100),
    mother_occupation character varying(100),
    brothers smallint,
    brothers_married smallint,
    sisters smallint,
    sisters_married smallint,
    family_type character varying(20),
    family_status character varying(20),
    family_values character varying(20),
    native_place character varying(100)
);

-- Name: profile_horoscope; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.profile_horoscope (
    profile_id uuid NOT NULL,
    rashi character varying(30),
    nakshatra character varying(30),
    manglik character varying(20),
    birth_time time without time zone,
    birth_place character varying(100),
    gotra character varying(60),
    visible_to character varying(20) NOT NULL
);

-- Name: profile_views; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.profile_views (
    id bigint NOT NULL,
    viewer_id uuid NOT NULL,
    viewed_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: profile_views_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.profile_views_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: profile_views_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.profile_views_id_seq OWNED BY public.profile_views.id;

-- Name: profiles; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    public_id character varying(12) NOT NULL,
    created_by character varying(20) NOT NULL,
    candidate_phone_hash character varying(64),
    candidate_phone_enc bytea,
    candidate_consent_at timestamp with time zone,
    first_name character varying(60) NOT NULL,
    last_name character varying(60),
    gender character varying(10) NOT NULL,
    dob date NOT NULL,
    height_cm smallint,
    marital_status character varying(20) NOT NULL,
    has_children boolean,
    religion_id integer NOT NULL,
    community_id integer,
    sub_community_id integer,
    mother_tongue_id integer,
    city_id integer,
    diet character varying(20),
    smoke character varying(20),
    drink character varying(20),
    about_me text,
    status character varying(20) NOT NULL,
    completeness smallint NOT NULL,
    is_premium boolean NOT NULL,
    last_active_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.refresh_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_hash character varying(64) NOT NULL,
    family_id uuid NOT NULL,
    device_id character varying(100),
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: religions; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.religions (
    id integer NOT NULL,
    name character varying(80) NOT NULL,
    sort smallint NOT NULL,
    active boolean NOT NULL
);

-- Name: religions_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.religions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: religions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.religions_id_seq OWNED BY public.religions.id;

-- Name: reports; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.reports (
    id uuid NOT NULL,
    reporter_id uuid NOT NULL,
    reported_id uuid NOT NULL,
    reason character varying(30) NOT NULL,
    details text,
    message_id bigint,
    status character varying(20) NOT NULL,
    resolved_by uuid,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: shortlists; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.shortlists (
    owner_id uuid NOT NULL,
    target_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: states; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.states (
    id integer NOT NULL,
    country_id integer NOT NULL,
    name character varying(80) NOT NULL
);

-- Name: states_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.states_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: states_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.states_id_seq OWNED BY public.states.id;

-- Name: sub_communities; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.sub_communities (
    id integer NOT NULL,
    community_id integer NOT NULL,
    name character varying(120) NOT NULL
);

-- Name: sub_communities_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.sub_communities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Name: sub_communities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.sub_communities_id_seq OWNED BY public.sub_communities.id;

-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.subscriptions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    plan_id integer NOT NULL,
    payment_id uuid,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    credits_total integer NOT NULL,
    credits_used integer NOT NULL,
    status character varying(20) NOT NULL,
    CONSTRAINT ck_subscriptions_credits CHECK ((credits_used <= credits_total))
);

-- Name: users; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.users (
    id uuid NOT NULL,
    phone_hash character varying(64) NOT NULL,
    phone_enc bytea NOT NULL,
    phone_verified_at timestamp with time zone,
    email_hash character varying(64),
    email_enc bytea,
    email_verified_at timestamp with time zone,
    role character varying(20) NOT NULL,
    status character varying(20) NOT NULL,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);

-- Name: verifications; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.verifications (
    id uuid NOT NULL,
    profile_id uuid NOT NULL,
    type character varying(30) NOT NULL,
    status character varying(20) NOT NULL,
    provider character varying(30),
    provider_ref character varying(100),
    masked_id character varying(30),
    verified_name character varying(120),
    verified_yob smallint,
    verified_gender character varying(10),
    name_match_score double precision,
    verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Name: admin_actions id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.admin_actions ALTER COLUMN id SET DEFAULT nextval('public.admin_actions_id_seq'::regclass);

-- Name: cities id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.cities ALTER COLUMN id SET DEFAULT nextval('public.cities_id_seq'::regclass);

-- Name: communities id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.communities ALTER COLUMN id SET DEFAULT nextval('public.communities_id_seq'::regclass);

-- Name: consents id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.consents ALTER COLUMN id SET DEFAULT nextval('public.consents_id_seq'::regclass);

-- Name: countries id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.countries ALTER COLUMN id SET DEFAULT nextval('public.countries_id_seq'::regclass);

-- Name: education_levels id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.education_levels ALTER COLUMN id SET DEFAULT nextval('public.education_levels_id_seq'::regclass);

-- Name: messages id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.messages ALTER COLUMN id SET DEFAULT nextval('public.messages_id_seq'::regclass);

-- Name: mother_tongues id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.mother_tongues ALTER COLUMN id SET DEFAULT nextval('public.mother_tongues_id_seq'::regclass);

-- Name: occupations id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.occupations ALTER COLUMN id SET DEFAULT nextval('public.occupations_id_seq'::regclass);

-- Name: plans id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.plans ALTER COLUMN id SET DEFAULT nextval('public.plans_id_seq'::regclass);

-- Name: profile_views id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_views ALTER COLUMN id SET DEFAULT nextval('public.profile_views_id_seq'::regclass);

-- Name: religions id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.religions ALTER COLUMN id SET DEFAULT nextval('public.religions_id_seq'::regclass);

-- Name: states id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.states ALTER COLUMN id SET DEFAULT nextval('public.states_id_seq'::regclass);

-- Name: sub_communities id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.sub_communities ALTER COLUMN id SET DEFAULT nextval('public.sub_communities_id_seq'::regclass);

-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);

-- Name: admin_actions pk_admin_actions; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.admin_actions
    ADD CONSTRAINT pk_admin_actions PRIMARY KEY (id);

-- Name: blocks pk_blocks; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT pk_blocks PRIMARY KEY (blocker_id, blocked_id);

-- Name: cities pk_cities; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT pk_cities PRIMARY KEY (id);

-- Name: communities pk_communities; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT pk_communities PRIMARY KEY (id);

-- Name: consents pk_consents; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT pk_consents PRIMARY KEY (id);

-- Name: contact_unlocks pk_contact_unlocks; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.contact_unlocks
    ADD CONSTRAINT pk_contact_unlocks PRIMARY KEY (viewer_id, target_id);

-- Name: conversations pk_conversations; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT pk_conversations PRIMARY KEY (id);

-- Name: countries pk_countries; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT pk_countries PRIMARY KEY (id);

-- Name: daily_matches pk_daily_matches; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.daily_matches
    ADD CONSTRAINT pk_daily_matches PRIMARY KEY (profile_id, for_date, match_id);

-- Name: devices pk_devices; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT pk_devices PRIMARY KEY (id);

-- Name: education_levels pk_education_levels; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.education_levels
    ADD CONSTRAINT pk_education_levels PRIMARY KEY (id);

-- Name: interests pk_interests; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT pk_interests PRIMARY KEY (id);

-- Name: messages pk_messages; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT pk_messages PRIMARY KEY (id);

-- Name: mother_tongues pk_mother_tongues; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.mother_tongues
    ADD CONSTRAINT pk_mother_tongues PRIMARY KEY (id);

-- Name: occupations pk_occupations; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.occupations
    ADD CONSTRAINT pk_occupations PRIMARY KEY (id);

-- Name: partner_preferences pk_partner_preferences; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.partner_preferences
    ADD CONSTRAINT pk_partner_preferences PRIMARY KEY (profile_id);

-- Name: payments pk_payments; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT pk_payments PRIMARY KEY (id);

-- Name: photos pk_photos; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.photos
    ADD CONSTRAINT pk_photos PRIMARY KEY (id);

-- Name: plans pk_plans; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT pk_plans PRIMARY KEY (id);

-- Name: privacy_settings pk_privacy_settings; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.privacy_settings
    ADD CONSTRAINT pk_privacy_settings PRIMARY KEY (profile_id);

-- Name: profile_career pk_profile_career; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_career
    ADD CONSTRAINT pk_profile_career PRIMARY KEY (profile_id);

-- Name: profile_family pk_profile_family; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_family
    ADD CONSTRAINT pk_profile_family PRIMARY KEY (profile_id);

-- Name: profile_horoscope pk_profile_horoscope; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_horoscope
    ADD CONSTRAINT pk_profile_horoscope PRIMARY KEY (profile_id);

-- Name: profile_views pk_profile_views; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_views
    ADD CONSTRAINT pk_profile_views PRIMARY KEY (id);

-- Name: profiles pk_profiles; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT pk_profiles PRIMARY KEY (id);

-- Name: refresh_tokens pk_refresh_tokens; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT pk_refresh_tokens PRIMARY KEY (id);

-- Name: religions pk_religions; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.religions
    ADD CONSTRAINT pk_religions PRIMARY KEY (id);

-- Name: reports pk_reports; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT pk_reports PRIMARY KEY (id);

-- Name: shortlists pk_shortlists; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.shortlists
    ADD CONSTRAINT pk_shortlists PRIMARY KEY (owner_id, target_id);

-- Name: states pk_states; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.states
    ADD CONSTRAINT pk_states PRIMARY KEY (id);

-- Name: sub_communities pk_sub_communities; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.sub_communities
    ADD CONSTRAINT pk_sub_communities PRIMARY KEY (id);

-- Name: subscriptions pk_subscriptions; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT pk_subscriptions PRIMARY KEY (id);

-- Name: users pk_users; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.users
    ADD CONSTRAINT pk_users PRIMARY KEY (id);

-- Name: verifications pk_verifications; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.verifications
    ADD CONSTRAINT pk_verifications PRIMARY KEY (id);

-- Name: communities uq_community_religion_name; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT uq_community_religion_name UNIQUE (religion_id, name);

-- Name: conversations uq_conversations_interest_id; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT uq_conversations_interest_id UNIQUE (interest_id);

-- Name: countries uq_countries_iso2; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT uq_countries_iso2 UNIQUE (iso2);

-- Name: mother_tongues uq_mother_tongues_name; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.mother_tongues
    ADD CONSTRAINT uq_mother_tongues_name UNIQUE (name);

-- Name: payments uq_payments_razorpay_order_id; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT uq_payments_razorpay_order_id UNIQUE (razorpay_order_id);

-- Name: payments uq_payments_razorpay_payment_id; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT uq_payments_razorpay_payment_id UNIQUE (razorpay_payment_id);

-- Name: plans uq_plans_code; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT uq_plans_code UNIQUE (code);

-- Name: profiles uq_profiles_candidate_phone_hash; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT uq_profiles_candidate_phone_hash UNIQUE (candidate_phone_hash);

-- Name: profiles uq_profiles_public_id; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT uq_profiles_public_id UNIQUE (public_id);

-- Name: profiles uq_profiles_user_id; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT uq_profiles_user_id UNIQUE (user_id);

-- Name: refresh_tokens uq_refresh_tokens_token_hash; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT uq_refresh_tokens_token_hash UNIQUE (token_hash);

-- Name: religions uq_religions_name; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.religions
    ADD CONSTRAINT uq_religions_name UNIQUE (name);

-- Name: sub_communities uq_subcommunity_comm_name; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.sub_communities
    ADD CONSTRAINT uq_subcommunity_comm_name UNIQUE (community_id, name);

-- Name: subscriptions uq_subscriptions_payment_id; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT uq_subscriptions_payment_id UNIQUE (payment_id);

-- Name: users uq_users_email_hash; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.users
    ADD CONSTRAINT uq_users_email_hash UNIQUE (email_hash);

-- Name: users uq_users_phone_hash; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.users
    ADD CONSTRAINT uq_users_phone_hash UNIQUE (phone_hash);

-- Name: verifications uq_verification_profile_type; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.verifications
    ADD CONSTRAINT uq_verification_profile_type UNIQUE (profile_id, type);

-- Name: ix_blocks_blocked_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_blocks_blocked_id ON public.blocks USING btree (blocked_id);

-- Name: ix_cities_state_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_cities_state_id ON public.cities USING btree (state_id);

-- Name: ix_communities_religion_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_communities_religion_id ON public.communities USING btree (religion_id);

-- Name: ix_consents_user_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_consents_user_id ON public.consents USING btree (user_id);

-- Name: ix_conversations_profile_a; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_conversations_profile_a ON public.conversations USING btree (profile_a);

-- Name: ix_conversations_profile_b; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_conversations_profile_b ON public.conversations USING btree (profile_b);

-- Name: ix_devices_fingerprint; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_devices_fingerprint ON public.devices USING btree (fingerprint);

-- Name: ix_devices_user_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_devices_user_id ON public.devices USING btree (user_id);

-- Name: ix_interest_receiver; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_interest_receiver ON public.interests USING btree (receiver_id, status, created_at);

-- Name: ix_messages_conv_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_messages_conv_id ON public.messages USING btree (conversation_id, id);

-- Name: ix_payments_user_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_payments_user_id ON public.payments USING btree (user_id);

-- Name: ix_photos_phash; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_photos_phash ON public.photos USING btree (phash);

-- Name: ix_photos_profile_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_photos_profile_id ON public.photos USING btree (profile_id);

-- Name: ix_pref_community_ids; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_pref_community_ids ON public.partner_preferences USING gin (community_ids);

-- Name: ix_profile_views_viewed; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_profile_views_viewed ON public.profile_views USING btree (viewed_id, created_at);

-- Name: ix_profiles_city_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_profiles_city_id ON public.profiles USING btree (city_id);

-- Name: ix_profiles_search; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_profiles_search ON public.profiles USING btree (status, gender, religion_id, community_id, dob, height_cm);

-- Name: ix_refresh_tokens_family_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_refresh_tokens_family_id ON public.refresh_tokens USING btree (family_id);

-- Name: ix_refresh_tokens_user_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_refresh_tokens_user_id ON public.refresh_tokens USING btree (user_id);

-- Name: ix_reports_reported_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_reports_reported_id ON public.reports USING btree (reported_id);

-- Name: ix_reports_status; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_reports_status ON public.reports USING btree (status);

-- Name: ix_states_country_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_states_country_id ON public.states USING btree (country_id);

-- Name: ix_sub_communities_community_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_sub_communities_community_id ON public.sub_communities USING btree (community_id);

-- Name: ix_subscriptions_ends_at; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_subscriptions_ends_at ON public.subscriptions USING btree (ends_at);

-- Name: ix_subscriptions_user_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX ix_subscriptions_user_id ON public.subscriptions USING btree (user_id);

-- Name: ux_interest_pair; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX ux_interest_pair ON public.interests USING btree (LEAST(sender_id, receiver_id), GREATEST(sender_id, receiver_id)) WHERE ((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying])::text[]));

-- Name: admin_actions fk_admin_actions_admin_id_users; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.admin_actions
    ADD CONSTRAINT fk_admin_actions_admin_id_users FOREIGN KEY (admin_id) REFERENCES public.users(id);

-- Name: blocks fk_blocks_blocked_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT fk_blocks_blocked_id_profiles FOREIGN KEY (blocked_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: blocks fk_blocks_blocker_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT fk_blocks_blocker_id_profiles FOREIGN KEY (blocker_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: cities fk_cities_state_id_states; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT fk_cities_state_id_states FOREIGN KEY (state_id) REFERENCES public.states(id);

-- Name: communities fk_communities_religion_id_religions; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT fk_communities_religion_id_religions FOREIGN KEY (religion_id) REFERENCES public.religions(id);

-- Name: consents fk_consents_user_id_users; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT fk_consents_user_id_users FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- Name: contact_unlocks fk_contact_unlocks_subscription_id_subscriptions; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.contact_unlocks
    ADD CONSTRAINT fk_contact_unlocks_subscription_id_subscriptions FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);

-- Name: contact_unlocks fk_contact_unlocks_target_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.contact_unlocks
    ADD CONSTRAINT fk_contact_unlocks_target_id_profiles FOREIGN KEY (target_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: contact_unlocks fk_contact_unlocks_viewer_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.contact_unlocks
    ADD CONSTRAINT fk_contact_unlocks_viewer_id_profiles FOREIGN KEY (viewer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: conversations fk_conversations_interest_id_interests; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT fk_conversations_interest_id_interests FOREIGN KEY (interest_id) REFERENCES public.interests(id);

-- Name: conversations fk_conversations_profile_a_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT fk_conversations_profile_a_profiles FOREIGN KEY (profile_a) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: conversations fk_conversations_profile_b_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT fk_conversations_profile_b_profiles FOREIGN KEY (profile_b) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: daily_matches fk_daily_matches_match_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.daily_matches
    ADD CONSTRAINT fk_daily_matches_match_id_profiles FOREIGN KEY (match_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: daily_matches fk_daily_matches_profile_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.daily_matches
    ADD CONSTRAINT fk_daily_matches_profile_id_profiles FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: devices fk_devices_user_id_users; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT fk_devices_user_id_users FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- Name: interests fk_interests_receiver_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT fk_interests_receiver_id_profiles FOREIGN KEY (receiver_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: interests fk_interests_sender_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT fk_interests_sender_id_profiles FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: messages fk_messages_conversation_id_conversations; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_messages_conversation_id_conversations FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;

-- Name: messages fk_messages_sender_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_messages_sender_id_profiles FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: partner_preferences fk_partner_preferences_profile_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.partner_preferences
    ADD CONSTRAINT fk_partner_preferences_profile_id_profiles FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: payments fk_payments_plan_id_plans; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_plan_id_plans FOREIGN KEY (plan_id) REFERENCES public.plans(id);

-- Name: payments fk_payments_user_id_users; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_user_id_users FOREIGN KEY (user_id) REFERENCES public.users(id);

-- Name: photos fk_photos_profile_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.photos
    ADD CONSTRAINT fk_photos_profile_id_profiles FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: privacy_settings fk_privacy_settings_profile_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.privacy_settings
    ADD CONSTRAINT fk_privacy_settings_profile_id_profiles FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: profile_career fk_profile_career_education_level_id_education_levels; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_career
    ADD CONSTRAINT fk_profile_career_education_level_id_education_levels FOREIGN KEY (education_level_id) REFERENCES public.education_levels(id);

-- Name: profile_career fk_profile_career_occupation_id_occupations; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_career
    ADD CONSTRAINT fk_profile_career_occupation_id_occupations FOREIGN KEY (occupation_id) REFERENCES public.occupations(id);

-- Name: profile_career fk_profile_career_profile_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_career
    ADD CONSTRAINT fk_profile_career_profile_id_profiles FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: profile_family fk_profile_family_profile_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_family
    ADD CONSTRAINT fk_profile_family_profile_id_profiles FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: profile_horoscope fk_profile_horoscope_profile_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_horoscope
    ADD CONSTRAINT fk_profile_horoscope_profile_id_profiles FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: profile_views fk_profile_views_viewed_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_views
    ADD CONSTRAINT fk_profile_views_viewed_id_profiles FOREIGN KEY (viewed_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: profile_views fk_profile_views_viewer_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profile_views
    ADD CONSTRAINT fk_profile_views_viewer_id_profiles FOREIGN KEY (viewer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: profiles fk_profiles_city_id_cities; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_profiles_city_id_cities FOREIGN KEY (city_id) REFERENCES public.cities(id);

-- Name: profiles fk_profiles_community_id_communities; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_profiles_community_id_communities FOREIGN KEY (community_id) REFERENCES public.communities(id);

-- Name: profiles fk_profiles_mother_tongue_id_mother_tongues; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_profiles_mother_tongue_id_mother_tongues FOREIGN KEY (mother_tongue_id) REFERENCES public.mother_tongues(id);

-- Name: profiles fk_profiles_religion_id_religions; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_profiles_religion_id_religions FOREIGN KEY (religion_id) REFERENCES public.religions(id);

-- Name: profiles fk_profiles_sub_community_id_sub_communities; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_profiles_sub_community_id_sub_communities FOREIGN KEY (sub_community_id) REFERENCES public.sub_communities(id);

-- Name: profiles fk_profiles_user_id_users; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_profiles_user_id_users FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- Name: refresh_tokens fk_refresh_tokens_user_id_users; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_user_id_users FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- Name: reports fk_reports_message_id_messages; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_message_id_messages FOREIGN KEY (message_id) REFERENCES public.messages(id);

-- Name: reports fk_reports_reported_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_reported_id_profiles FOREIGN KEY (reported_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: reports fk_reports_reporter_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_reporter_id_profiles FOREIGN KEY (reporter_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: reports fk_reports_resolved_by_users; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_resolved_by_users FOREIGN KEY (resolved_by) REFERENCES public.users(id);

-- Name: shortlists fk_shortlists_owner_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.shortlists
    ADD CONSTRAINT fk_shortlists_owner_id_profiles FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: shortlists fk_shortlists_target_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.shortlists
    ADD CONSTRAINT fk_shortlists_target_id_profiles FOREIGN KEY (target_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Name: states fk_states_country_id_countries; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.states
    ADD CONSTRAINT fk_states_country_id_countries FOREIGN KEY (country_id) REFERENCES public.countries(id);

-- Name: sub_communities fk_sub_communities_community_id_communities; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.sub_communities
    ADD CONSTRAINT fk_sub_communities_community_id_communities FOREIGN KEY (community_id) REFERENCES public.communities(id);

-- Name: subscriptions fk_subscriptions_payment_id_payments; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_subscriptions_payment_id_payments FOREIGN KEY (payment_id) REFERENCES public.payments(id);

-- Name: subscriptions fk_subscriptions_plan_id_plans; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_subscriptions_plan_id_plans FOREIGN KEY (plan_id) REFERENCES public.plans(id);

-- Name: subscriptions fk_subscriptions_user_id_users; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_subscriptions_user_id_users FOREIGN KEY (user_id) REFERENCES public.users(id);

-- Name: verifications fk_verifications_profile_id_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.verifications
    ADD CONSTRAINT fk_verifications_profile_id_profiles FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- PostgreSQL database dump complete

