-- ============================================================================
-- Материализованный вид passenger_info с агрегированными данными по пассажирам: 
-- число перелётов, избранные города, аэропорты, места и т.д.
-- ============================================================================

-- CTE: подсчитываем число перелётов на каждый билет
WITH flight_counts AS (
    SELECT
        t.passenger_id,
        COUNT(tf.flight_id) AS flights_per_ticket
    FROM bookings.tickets t
    JOIN bookings.ticket_flights tf
      ON t.ticket_no = tf.ticket_no
    GROUP BY t.passenger_id
),

-- CTE: находим самый частый город вылета и прилёта (NULL при нескольких равных)
most_common_cities AS (
    WITH city_counts AS (
        SELECT
            t.passenger_id,
            a.city,
            COUNT(*) AS city_count,
            CASE
               WHEN f.departure_airport = a.airport_code THEN 'departure'
               ELSE 'arrival'
            END AS airport_type
        FROM bookings.tickets t
        JOIN bookings.ticket_flights tf ON t.ticket_no = tf.ticket_no
        JOIN bookings.flights f ON tf.flight_id = f.flight_id
        JOIN bookings.airports a
          ON a.airport_code IN (f.departure_airport, f.arrival_airport)
        GROUP BY t.passenger_id, a.city, airport_type
    ),
    ranked_cities AS (
        SELECT
            passenger_id,
            city,
            airport_type,
            city_count,
            RANK() OVER (
              PARTITION BY passenger_id, airport_type
              ORDER BY city_count DESC
            ) AS city_rank
        FROM city_counts
    )
    SELECT
        passenger_id,
        -- если два города лидируют одинаково, вернём NULL
        CASE
          WHEN COUNT(*) FILTER (WHERE airport_type='departure' AND city_rank=1)>1
            THEN NULL
          ELSE MAX(city) FILTER (WHERE airport_type='departure' AND city_rank=1)
        END AS most_often_city_from,
        CASE
          WHEN COUNT(*) FILTER (WHERE airport_type='arrival' AND city_rank=1)>1
            THEN NULL
          ELSE MAX(city) FILTER (WHERE airport_type='arrival' AND city_rank=1)
        END AS most_often_city_to
    FROM ranked_cities
    GROUP BY passenger_id
),

-- … (остальные CTE: most_common_airport, most_common_seat) …

SELECT
    t.passenger_id,
    COUNT(DISTINCT t.ticket_no)         AS total_tickets,
    SUM(tf.amount)                      AS total_tickets_amount,
    AVG(tf.amount)                      AS avg_tickets_amount,
    AVG(fc.flights_per_ticket)          AS average_flights,
    mc.most_often_city_from,
    mc.most_often_city_to,
    ma.preffered_airport,
    ms.preffered_seat,
    MODE() WITHIN GROUP (ORDER BY tf.fare_conditions) AS preffered_conditions,
    MAX(t.contact_data::JSONB ->> 'phone')     AS phone_number,
    MAX(t.contact_data::JSONB ->> 'email')     AS email,
    MAX(t.passenger_name)                     AS fio,
    SUM(a.range)                              AS total_range
FROM bookings.tickets t
JOIN bookings.ticket_flights tf ON t.ticket_no = tf.ticket_no
JOIN bookings.flights f ON tf.flight_id = f.flight_id
JOIN bookings.aircrafts a ON f.aircraft_code = a.aircraft_code
JOIN flight_counts fc ON t.passenger_id = fc.passenger_id
LEFT JOIN most_common_cities mc ON t.passenger_id = mc.passenger_id
LEFT JOIN most_common_airport ma ON t.passenger_id = ma.passenger_id
LEFT JOIN most_common_seat ms ON t.passenger_id = ms.passenger_id
GROUP BY
    t.passenger_id,
    mc.most_often_city_from,
    mc.most_often_city_to,
    ma.preffered_airport,
    ms.preffered_seat
ORDER BY t.passenger_id DESC
WITH DATA;

-- для проверки:
SELECT * FROM passenger_info;
