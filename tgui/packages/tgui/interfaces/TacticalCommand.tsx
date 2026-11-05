import { useState } from 'react';
import {
  Box,
  Button,
  Dropdown,
  Input,
  NoticeBox,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';
import { decodeHtmlEntities } from 'tgui-core/string';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type Point = { x: number; y: number };
type Span = [number, number, number];
type Marker = Point & { id: string; kind: string; direction: number };
type Zone = {
  id: string;
  name: string;
  purpose: string;
  count: number;
  spans: Span[];
  markers: Marker[];
};
type Route = {
  id: string;
  name: string;
  loop: number;
  points: Point[];
};
type Member = {
  id: string;
  name: string;
  status: string;
  z: number;
  health: number;
};
type Squad = {
  id: string;
  name: string;
  order: string;
  status: string;
  zone: string | null;
  route: string | null;
  fallback: string | null;
  waypoint: number;
  zone_name: string | null;
  route_name: string | null;
  fallback_name: string | null;
  members: Member[];
};
type Recruit = {
  id: string;
  name: string;
  squad: string | null;
  squad_name: string | null;
};
type Friendly = Point & {
  name: string;
  player: number;
  self: number;
  squad: string | null;
};
type Data = {
  z: number;
  revision: number;
  faction: string;
  tool: string;
  marker_direction: number;
  notice: string;
  notice_error: number;
  selected_squad: string | null;
  selected_zone: string | null;
  selected_route: string | null;
  map: string | null;
  offset_x: number;
  offset_y: number;
  max_x: number;
  max_y: number;
  cursor: Point | null;
  anchor: Point | null;
  preview: Span[];
  preview_count: number;
  draft_route: Point[];
  zones: Zone[];
  routes: Route[];
  squads: Squad[];
  recruits: Recruit[];
  friendlies: Friendly[];
};

const purposeColors: Record<string, string> = {
  guard: '#58d9ff',
  fallback: '#d49aff',
  staging: '#ffd66b',
};
const tools = [
  ['inspect', 'crosshairs', 'Target'],
  ['rectangle', 'vector-square', 'Rectangle'],
  ['room', 'draw-polygon', 'Room'],
  ['route', 'route', 'Route'],
  ['entrance', 'door-open', 'Entrance'],
  ['choke', 'compress-arrows-alt', 'Choke'],
];
const toolHelp: Record<string, string> = {
  inspect:
    'Click terrain to choose a hold target. No orders are sent by clicking.',
  rectangle:
    'Click two opposite corners, review the shaded footprint, then Save zone.',
  room: 'Click a room to preview its exact mapped area, then Save zone. For large outdoor areas use Rectangle.',
  route:
    'Click waypoints in patrol order. Undo removes the last point. Save with at least two points.',
  entrance:
    'Select a saved zone, then click an entrance in or beside it. Markers guide guard positions.',
  choke:
    'Select a saved zone, then click a choke point in or beside it. Markers guide guard positions.',
};

export const TacticalCommand = () => {
  const { act, data: rawData } = useBackend<Data>();
  // Labels stay HTML-safe on the server; React receives decoded text, never markup.
  const decode = (value: string | null) => decodeHtmlEntities(value || '');
  const data: Data = {
    ...rawData,
    notice: decode(rawData.notice),
    squads: rawData.squads.map((entry) => ({
      ...entry,
      name: decode(entry.name),
      zone_name: decode(entry.zone_name),
      route_name: decode(entry.route_name),
      fallback_name: decode(entry.fallback_name),
      members: entry.members.map((member) => ({
        ...member,
        name: decode(member.name),
      })),
    })),
    zones: rawData.zones.map((entry) => ({
      ...entry,
      name: decode(entry.name),
    })),
    routes: rawData.routes.map((entry) => ({
      ...entry,
      name: decode(entry.name),
    })),
    recruits: rawData.recruits.map((entry) => ({
      ...entry,
      name: decode(entry.name),
      squad_name: decode(entry.squad_name),
    })),
    friendlies: rawData.friendlies.map((entry) => ({
      ...entry,
      name: decode(entry.name),
    })),
  };
  const [tab, setTab] = useState('squads');
  const [name, setName] = useState('');
  const [purpose, setPurpose] = useState('guard');
  const [loop, setLoop] = useState(true);
  const [zoom, setZoom] = useState(1);
  const send = (action: string, params: Record<string, unknown> = {}) =>
    act(action, { ...params, z: data.z });
  const squad = data.squads.find((item) => item.id === data.selected_squad);
  const zone = data.zones.find((item) => item.id === data.selected_zone);
  const route = data.routes.find((item) => item.id === data.selected_route);
  const isDrawing = data.tool === 'rectangle' || data.tool === 'room';

  return (
    <Window width={1180} height={900} title="Tactical Command">
      <Window.Content scrollable>
        <Stack align="center" mb={1}>
          <Stack.Item grow>
            <Box fontSize="20px" bold color="#75ddff">
              TACTICAL COMMAND
            </Box>
            <Box color="label">
              {data.faction} / Level {data.z} / {data.squads.length} tactical
              squads
            </Box>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="mouse-pointer"
              onClick={() => send('deselect')}
              tooltip="Clear your selection and drawing tool. All squads keep their orders."
            >
              Deselect — keep orders
            </Button>
          </Stack.Item>
        </Stack>
        {data.notice_error ? (
          <NoticeBox danger>{data.notice}</NoticeBox>
        ) : (
          <NoticeBox info>{data.notice}</NoticeBox>
        )}
        <Stack align="stretch">
          <Stack.Item grow basis="65%" minWidth={0}>
            <Section
              title="Operations map"
              buttons={
                <>
                  <Button
                    icon="search-minus"
                    disabled={zoom <= 1}
                    onClick={() => setZoom(Math.max(1, zoom - 0.5))}
                  />
                  <Button onClick={() => setZoom(1)}>{zoom}×</Button>
                  <Button
                    icon="search-plus"
                    disabled={zoom >= 3}
                    onClick={() => setZoom(Math.min(3, zoom + 0.5))}
                  />
                </>
              }
            >
              <Box mb={1}>
                {tools.map(([id, icon, label]) => (
                  <Button
                    key={id}
                    icon={icon}
                    selected={data.tool === id}
                    disabled={(id === 'entrance' || id === 'choke') && !zone}
                    onClick={() => {
                      send('tool', { tool: id });
                      if (id === 'rectangle' || id === 'room') setTab('zones');
                      if (id === 'route') setTab('routes');
                    }}
                  >
                    {label}
                  </Button>
                ))}
              </Box>
              <Box color="label" mb={1} minHeight="30px">
                {toolHelp[data.tool]}
              </Box>
              {(data.tool === 'entrance' || data.tool === 'choke') && (
                <Box mb={1}>
                  <Box inline mr={1} color="label">
                    Marker facing
                  </Box>
                  {[
                    [1, '↑ North'],
                    [4, '→ East'],
                    [2, '↓ South'],
                    [8, '← West'],
                  ].map(([direction, label]) => (
                    <Button
                      key={direction}
                      selected={data.marker_direction === direction}
                      onClick={() => send('marker_facing', { direction })}
                    >
                      {label}
                    </Button>
                  ))}
                </Box>
              )}
              <TacticalMap
                data={data}
                zoom={zoom}
                onPoint={(point) => send('map_click', point)}
              />
              <Stack mt={1} align="center">
                <Stack.Item grow color="label">
                  <span style={{ color: '#7be4ff' }}>● Allied AI</span>
                  {' · '}
                  <span style={{ color: '#ffffff' }}>◆ Players</span>
                  {' · '}
                  <span style={{ color: '#ffd66b' }}>⊕ You</span>
                  <Box fontSize="11px">
                    Static terrain + friendly positions only. No enemy tracking.
                  </Box>
                </Stack.Item>
                <Stack.Item>
                  <Box>
                    Target:{' '}
                    {data.cursor ? `${data.cursor.x}, ${data.cursor.y}` : '—'}
                  </Box>
                  <Button
                    icon="undo"
                    disabled={
                      !data.preview_count &&
                      !data.anchor &&
                      !data.draft_route.length
                    }
                    onClick={() => send('clear_draft')}
                  >
                    Clear draft
                  </Button>
                </Stack.Item>
              </Stack>
            </Section>
            <Section
              title={
                squad
                  ? `${squad.name} · ${squad.members.length}/24 marines`
                  : 'Squad roster'
              }
            >
              {!squad && (
                <Box color="label">
                  Create or select a squad in the panel on the right.
                </Box>
              )}
              {squad && !squad.members.length && (
                <NoticeBox>
                  No members yet. Move within seven tiles of allied AI and
                  recruit them below.
                </NoticeBox>
              )}
              {squad?.members.map((member) => (
                <Stack key={member.id} align="center" mb={0.5}>
                  <Stack.Item grow basis="40%">
                    <Box bold>{member.name}</Box>
                    <Box color="label" fontSize="11px">
                      Level {member.z} · Health {member.health}
                    </Box>
                  </Stack.Item>
                  <Stack.Item grow basis="40%">
                    <Box
                      color={
                        member.status.toLowerCase().includes('block')
                          ? 'orange'
                          : 'label'
                      }
                    >
                      {member.status}
                    </Box>
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      icon="user-minus"
                      tooltip="Release this marine to autonomous AI. Other squad members keep their order."
                      onClick={() => send('release', { id: member.id })}
                    >
                      Release
                    </Button>
                  </Stack.Item>
                </Stack>
              ))}
              {squad && (
                <Box mt={1} pt={1} style={{ borderTop: '1px solid #36515e' }}>
                  <Box bold mb={0.5}>
                    Nearby recruitment · seven-tile range
                  </Box>
                  {!data.recruits.filter(
                    (recruit) => recruit.squad !== squad.id,
                  ).length && (
                    <Box color="label">
                      No other recruitable allied AI nearby.
                    </Box>
                  )}
                  {data.recruits
                    .filter((recruit) => recruit.squad !== squad.id)
                    .map((recruit) => (
                      <Stack key={recruit.id} mb={0.5} align="center">
                        <Stack.Item grow>
                          {recruit.name}
                          {recruit.squad_name && (
                            <Box inline color="label">
                              {' '}
                              · {recruit.squad_name}
                            </Box>
                          )}
                        </Stack.Item>
                        <Stack.Item>
                          <Button
                            icon={recruit.squad ? 'exchange-alt' : 'user-plus'}
                            disabled={squad.members.length >= 24}
                            onClick={() =>
                              send(recruit.squad ? 'transfer' : 'recruit', {
                                id: recruit.id,
                              })
                            }
                          >
                            {recruit.squad ? 'Transfer here' : 'Recruit'}
                          </Button>
                        </Stack.Item>
                      </Stack>
                    ))}
                </Box>
              )}
            </Section>
          </Stack.Item>
          <Stack.Item basis="35%" minWidth="330px">
            <Section
              title={squad ? `Orders · ${squad.name}` : 'Persistent orders'}
            >
              {!squad ? (
                <Box color="label">Select a squad to assign orders.</Box>
              ) : (
                <>
                  <Box fontSize="17px" bold color="#75ddff" mb={0.5}>
                    {squad.order.toUpperCase()}
                  </Box>
                  <Box mb={1}>{squad.status}</Box>
                  <Box color="label" fontSize="11px" mb={1}>
                    Designator quick orders on a recruited marine command this
                    entire squad.
                  </Box>
                  {squad.zone_name && (
                    <Box mb={1} color="label">
                      Assigned zone: {squad.zone_name}
                    </Box>
                  )}
                  {squad.route_name && (
                    <Box mb={1} color="label">
                      Assigned route: {squad.route_name} · Waypoint{' '}
                      {squad.waypoint}
                    </Box>
                  )}
                  <Box mb={1}>
                    <Button
                      icon="walking"
                      onClick={() => send('order', { order: 'follow' })}
                    >
                      Follow me
                    </Button>
                    <Button
                      icon="hand-paper"
                      onClick={() => send('order', { order: 'hold' })}
                    >
                      Hold here
                    </Button>
                    <Button
                      icon="crosshairs"
                      disabled={!data.cursor}
                      onClick={() =>
                        send('order', { order: 'hold', at_cursor: true })
                      }
                    >
                      Hold at target
                    </Button>
                  </Box>
                  <Button
                    fluid
                    icon="shield-alt"
                    disabled={!zone}
                    mb={0.5}
                    onClick={() => send('order', { order: 'guard' })}
                  >
                    Guard {zone ? zone.name : '— select a zone'}
                  </Button>
                  <Button
                    fluid
                    icon="route"
                    disabled={!route}
                    mb={1}
                    onClick={() => send('order', { order: 'patrol' })}
                  >
                    Patrol {route ? route.name : '— select a route'}
                  </Button>
                  <Box color="label" mb={0.5}>
                    Fallback zone (does not order retreat)
                  </Box>
                  <Dropdown
                    width="100%"
                    selected={squad.fallback_name || 'No fallback'}
                    options={[
                      'No fallback',
                      ...data.zones.map(
                        (entry) => `${entry.name} [${entry.id}]`,
                      ),
                    ]}
                    onSelected={(value) =>
                      send('fallback', {
                        id:
                          data.zones.find(
                            (entry) => `${entry.name} [${entry.id}]` === value,
                          )?.id || null,
                      })
                    }
                  />
                  <Button
                    fluid
                    color="orange"
                    icon="undo-alt"
                    mt={0.5}
                    disabled={!squad.fallback}
                    onClick={() => send('order', { order: 'retreat' })}
                  >
                    Retreat to fallback
                  </Button>
                  <Box color="label" fontSize="11px" mt={1}>
                    Orders persist through combat. Retreat stays active until
                    reassigned. Deselect never stops a squad.
                  </Box>
                </>
              )}
            </Section>
            <Tabs fluid>
              <Tabs.Tab
                selected={tab === 'squads'}
                onClick={() => setTab('squads')}
              >
                Squads ({data.squads.length})
              </Tabs.Tab>
              <Tabs.Tab
                selected={tab === 'zones'}
                onClick={() => setTab('zones')}
              >
                Zones ({data.zones.length})
              </Tabs.Tab>
              <Tabs.Tab
                selected={tab === 'routes'}
                onClick={() => setTab('routes')}
              >
                Routes ({data.routes.length})
              </Tabs.Tab>
            </Tabs>
            <Section
              title={
                tab === 'squads'
                  ? 'Squad management'
                  : tab === 'zones'
                    ? 'Reusable zone library'
                    : 'Ordered patrol routes'
              }
            >
              <Input
                fluid
                placeholder={
                  tab === 'squads'
                    ? 'Squad name…'
                    : tab === 'zones'
                      ? 'Zone name…'
                      : 'Route name…'
                }
                maxLength={40}
                value={name}
                onChange={setName}
                mb={1}
              />
              {tab === 'squads' && (
                <>
                  <Button
                    fluid
                    icon="plus"
                    mb={1}
                    disabled={data.squads.length >= 16}
                    onClick={() => send('squad_create', { name })}
                  >
                    Create squad
                  </Button>
                  {data.squads.map((entry) => (
                    <Button
                      fluid
                      key={entry.id}
                      selected={entry.id === squad?.id}
                      mb={0.5}
                      onClick={() => {
                        send('squad_select', { id: entry.id });
                        setName(entry.name);
                      }}
                    >
                      {entry.name} · {entry.members.length} · {entry.order}
                    </Button>
                  ))}
                  {squad && (
                    <Box mt={1}>
                      <Button
                        icon="pen"
                        onClick={() => send('squad_rename', { name })}
                      >
                        Rename
                      </Button>
                      <Button.Confirm
                        color="bad"
                        icon="users-slash"
                        onClick={() => send('squad_delete')}
                      >
                        Disband squad
                      </Button.Confirm>
                      <Box color="label" mt={1} fontSize="11px">
                        Disband releases all members to autonomous AI. Use Hold
                        to stop movement without releasing them.
                      </Box>
                    </Box>
                  )}
                </>
              )}
              {tab === 'zones' && (
                <>
                  <Box color="label" mb={0.5}>
                    Classification
                  </Box>
                  <Dropdown
                    width="100%"
                    options={['guard', 'fallback', 'staging']}
                    selected={purpose}
                    onSelected={setPurpose}
                  />
                  <Button
                    fluid
                    icon="save"
                    mt={1}
                    mb={1}
                    disabled={!data.preview_count || !isDrawing}
                    onClick={() => send('zone_save', { name, purpose })}
                  >
                    Save preview ({data.preview_count} tiles)
                  </Button>
                  {!data.zones.length && (
                    <Box color="label">
                      Choose Rectangle or Room above the map, preview the
                      footprint, then save.
                    </Box>
                  )}
                  {data.zones.map((entry) => (
                    <Button
                      fluid
                      key={entry.id}
                      selected={zone?.id === entry.id}
                      mb={0.5}
                      onClick={() => {
                        send('zone_select', { id: entry.id });
                        setName(entry.name);
                        setPurpose(entry.purpose);
                      }}
                    >
                      {entry.name} · {entry.purpose} · {entry.count} tiles
                    </Button>
                  ))}
                  {zone && (
                    <Box mt={1}>
                      <Button
                        icon="pen"
                        onClick={() => send('zone_rename', { name })}
                      >
                        Rename
                      </Button>
                      <Button
                        icon="tags"
                        onClick={() => send('zone_purpose', { purpose })}
                      >
                        Reclassify
                      </Button>
                      <Button.Confirm
                        icon="trash"
                        color="bad"
                        onClick={() => send('zone_delete')}
                      >
                        Delete
                      </Button.Confirm>
                      <Box color="label" mt={1} fontSize="11px">
                        Reclassification preserves geometry and assignments.
                        Assigned zones cannot be deleted.
                      </Box>
                      <Box bold mt={1} mb={0.5}>
                        Entrances & choke points · {zone.markers.length}/16
                      </Box>
                      {!zone.markers.length && (
                        <Box color="label">
                          Use Entrance or Choke above the map to add guard
                          positions.
                        </Box>
                      )}
                      {zone.markers.map((marker) => (
                        <Stack key={marker.id} align="center" mb={0.5}>
                          <Stack.Item grow>
                            {marker.kind} · {marker.x}, {marker.y}
                          </Stack.Item>
                          <Stack.Item>
                            <Button
                              icon="times"
                              onClick={() =>
                                send('marker_delete', { id: marker.id })
                              }
                            />
                          </Stack.Item>
                        </Stack>
                      ))}
                    </Box>
                  )}
                </>
              )}
              {tab === 'routes' && (
                <>
                  <Button.Checkbox
                    checked={loop}
                    onClick={() => setLoop(!loop)}
                  >
                    {loop
                      ? 'Loop: last point → first'
                      : 'Shuttle: reverse at each end'}
                  </Button.Checkbox>
                  <Box mt={1} mb={1}>
                    <Button
                      icon="undo"
                      disabled={!data.draft_route.length}
                      onClick={() => send('route_undo')}
                    >
                      Undo point
                    </Button>
                    <Button
                      icon="save"
                      disabled={data.draft_route.length < 2}
                      onClick={() =>
                        send('route_save', { name, loop: loop ? 1 : 0 })
                      }
                    >
                      Save {data.draft_route.length} points
                    </Button>
                  </Box>
                  {!!data.draft_route.length && (
                    <Box color="label" mb={1}>
                      {data.draft_route
                        .map(
                          (point, index) =>
                            `${index + 1}: ${point.x},${point.y}`,
                        )
                        .join(' → ')}
                    </Box>
                  )}
                  {!data.routes.length && (
                    <Box color="label">
                      Choose Route above the map and click waypoints in patrol
                      order.
                    </Box>
                  )}
                  {data.routes.map((entry) => (
                    <Button
                      fluid
                      key={entry.id}
                      selected={route?.id === entry.id}
                      mb={0.5}
                      onClick={() => {
                        send('route_select', { id: entry.id });
                        setName(entry.name);
                      }}
                    >
                      {entry.name} · {entry.points.length} points ·{' '}
                      {entry.loop ? 'loop' : 'shuttle'}
                    </Button>
                  ))}
                  {route && (
                    <Box mt={1}>
                      <Button
                        icon="pen"
                        onClick={() => send('route_rename', { name })}
                      >
                        Rename
                      </Button>
                      <Button.Confirm
                        icon="trash"
                        color="bad"
                        onClick={() => send('route_delete')}
                      >
                        Delete
                      </Button.Confirm>
                      <Box color="label" mt={1}>
                        {route.points
                          .map(
                            (point, index) =>
                              `${index + 1}: ${point.x},${point.y}`,
                          )
                          .join(' → ')}
                      </Box>
                    </Box>
                  )}
                </>
              )}
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};

const TacticalMap = (props: {
  data: Data;
  zoom: number;
  onPoint: (point: Point) => void;
}) => {
  const { data, zoom, onPoint } = props;
  // SSminimaps paints two pixels per world tile, then shifts its static 480px image.
  const px = (x: number) => x * 2 - 1 + data.offset_x;
  const py = (y: number) => 481 - y * 2 - data.offset_y;
  const path = (spans: Span[]) =>
    spans
      .map(
        ([x, y, width]) =>
          `M${px(x) - 1},${py(y) - 1}h${width * 2}v2h${-width * 2}z`,
      )
      .join(' ');
  const points = (route: Point[]) =>
    route.map((point) => `${px(point.x)},${py(point.y)}`).join(' ');
  const selectedRoute = data.routes.find(
    (route) => route.id === data.selected_route,
  );

  return (
    <div
      style={{
        height: '490px',
        width: '100%',
        maxWidth: '100%',
        minWidth: 0,
        boxSizing: 'border-box',
        overflow: 'auto',
        background: '#071019',
        border: '1px solid #385766',
      }}
    >
      <svg
        viewBox="0 0 480 480"
        style={{
          display: 'block',
          width: `${zoom * 480}px`,
          height: `${zoom * 480}px`,
          margin: '0 auto',
          cursor: 'crosshair',
          background: '#071019',
        }}
        onClick={(event) => {
          const bounds = event.currentTarget.getBoundingClientRect();
          const x =
            Math.floor(
              (((event.clientX - bounds.left) / bounds.width) * 480 -
                data.offset_x) /
                2,
            ) + 1;
          const y =
            Math.floor(
              (480 -
                ((event.clientY - bounds.top) / bounds.height) * 480 -
                data.offset_y) /
                2,
            ) + 1;
          if (x >= 1 && x <= data.max_x && y >= 1 && y <= data.max_y) {
            onPoint({ x, y });
          }
        }}
      >
        <title>
          Tactical terrain map. Click to use the selected drawing tool.
        </title>
        {data.map && (
          <image
            href={`data:image/png;base64,${data.map}`}
            width="480"
            height="480"
          />
        )}
        {!data.map && (
          <text x="240" y="25" textAnchor="middle" fill="#9fb9c8" fontSize="10">
            Terrain unavailable on this level; coordinate map remains usable
          </text>
        )}
        <g pointerEvents="none">
          {data.zones.map((zone) => (
            <g key={zone.id}>
              <path
                d={path(zone.spans)}
                fill={purposeColors[zone.purpose]}
                fillOpacity={zone.id === data.selected_zone ? 0.38 : 0.16}
                stroke={purposeColors[zone.purpose]}
                strokeWidth={zone.id === data.selected_zone ? 0.5 : 0.15}
              />
              {zone.spans.length > 0 && (
                <text
                  x={px(zone.spans[0][0])}
                  y={py(zone.spans[0][1]) - 4}
                  fill={purposeColors[zone.purpose]}
                  fontSize="6"
                  stroke="#071019"
                  strokeWidth="1.4"
                  paintOrder="stroke"
                >
                  {zone.name}
                </text>
              )}
              {zone.markers.map((marker) => (
                <g
                  key={marker.id}
                  transform={`translate(${px(marker.x)} ${py(marker.y)})`}
                >
                  <line
                    x1="0"
                    y1="0"
                    x2={
                      marker.direction === 4
                        ? 7
                        : marker.direction === 8
                          ? -7
                          : 0
                    }
                    y2={
                      marker.direction === 1
                        ? -7
                        : marker.direction === 2
                          ? 7
                          : 0
                    }
                    stroke="#ffd66b"
                    strokeWidth="1.2"
                  />
                  {marker.kind === 'entrance' ? (
                    <rect
                      x="-2.5"
                      y="-2.5"
                      width="5"
                      height="5"
                      fill="#ffd66b"
                      stroke="#071019"
                      strokeWidth="0.7"
                    />
                  ) : (
                    <path
                      d="M0,-3 L3,0 L0,3 L-3,0Z"
                      fill="#ff9b67"
                      stroke="#071019"
                      strokeWidth="0.7"
                    />
                  )}
                </g>
              ))}
            </g>
          ))}
          {selectedRoute && (
            <>
              <polyline
                points={points(
                  selectedRoute.loop
                    ? [...selectedRoute.points, selectedRoute.points[0]]
                    : selectedRoute.points,
                )}
                fill="none"
                stroke="#8ef2aa"
                strokeWidth="1.4"
                strokeDasharray="4 2"
              />
              {selectedRoute.points.map((point, index) => (
                <g
                  key={index}
                  transform={`translate(${px(point.x)} ${py(point.y)})`}
                >
                  <circle
                    r="4"
                    fill="#143c24"
                    stroke="#8ef2aa"
                    strokeWidth="0.7"
                  />
                  <text
                    textAnchor="middle"
                    dominantBaseline="central"
                    fill="#ffffff"
                    fontSize="5"
                  >
                    {index + 1}
                  </text>
                </g>
              ))}
            </>
          )}
          <path
            d={path(data.preview)}
            fill="#ffe180"
            fillOpacity="0.4"
            stroke="#fff1ba"
            strokeWidth="0.35"
          />
          {data.anchor && !data.preview_count && (
            <circle
              cx={px(data.anchor.x)}
              cy={py(data.anchor.y)}
              r="4"
              stroke="#ffe180"
              strokeWidth="1"
              fill="none"
            />
          )}
          <polyline
            points={points(data.draft_route)}
            fill="none"
            stroke="#ffe180"
            strokeWidth="1.6"
          />
          {data.draft_route.map((point, index) => (
            <g
              key={index}
              transform={`translate(${px(point.x)} ${py(point.y)})`}
            >
              <circle r="4" fill="#655021" stroke="#ffe180" strokeWidth="0.7" />
              <text
                textAnchor="middle"
                dominantBaseline="central"
                fill="#ffffff"
                fontSize="5"
              >
                {index + 1}
              </text>
            </g>
          ))}
          {data.friendlies.map((friendly, index) => (
            <g
              key={index}
              transform={`translate(${px(friendly.x)} ${py(friendly.y)})`}
            >
              {friendly.squad && friendly.squad === data.selected_squad && (
                <circle r="4.5" stroke="#7be4ff" strokeWidth="1" fill="none" />
              )}
              {friendly.player ? (
                <path
                  d="M0,-2.8 L2.8,0 L0,2.8 L-2.8,0Z"
                  fill={friendly.self ? '#ffd66b' : '#ffffff'}
                  stroke="#071019"
                  strokeWidth="0.7"
                />
              ) : (
                <circle
                  r="1.8"
                  fill="#7be4ff"
                  stroke="#071019"
                  strokeWidth="0.5"
                />
              )}
              {friendly.self && (
                <circle r="5" stroke="#ffd66b" strokeWidth="0.8" fill="none" />
              )}
            </g>
          ))}
          {data.cursor && (
            <path
              d={`M${px(data.cursor.x) - 6},${py(data.cursor.y)}h12 M${px(data.cursor.x)},${py(data.cursor.y) - 6}v12`}
              stroke="#ffffff"
              strokeWidth="0.8"
            />
          )}
        </g>
      </svg>
    </div>
  );
};
